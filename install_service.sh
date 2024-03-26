#!/bin/bash

######################################################
# Scilab Flask Server Installation Script with EFS Support
#
# This script automates the setup of a Flask application designed to execute
# Scilab scripts, with the option to write results to an EFS drive.
#
# Requirements:
# - Ubuntu Linux (Tested on Ubuntu 20.04)
#
# Usage:
# 1. Ensure you have sudo privileges.
# 2. Save this script to a file, for example, install_scilab_flask_efs.sh.
# 3. Make the script executable: chmod +x install_scilab_flask_efs.sh
# 4. Run the script: ./install_scilab_flask_efs.sh
#
# Example calls:
# Execute Scilab instruction and get result directly:
# curl -X POST -H "Content-Type: text/plain" --data "disp(5*5);" http://localhost:5000/sci_instruct
#
# Execute Scilab instruction and write result to EFS (specify file name with query parameters):
# curl -X POST -H "Content-Type: text/plain" --data "disp(5*5);" "http://localhost:5000/sci_instruct?write_to_efs=true&results_file_name=result1.txt"
#
# Upload Scilab script file and get result directly:
# curl -s -o response.txt -w "%{http_code}" -F "file=@test_script.sci" http://localhost:5000/sci_script
#
# Upload Scilab script file and write result to EFS (specify file name with query parameters):
# curl -s -o response.txt -w "%{http_code}" -F "file=@test_script.sci" "http://localhost:5000/sci_script?write_to_efs=true&results_file_name=result2.txt"
#
# Author: John DeHart
# Created on: 2/08/2024
# Last Updated: 2/23/24
#
######################################################

# Configuration Variables
HOSTNAME="scilab-service"
INDEX_URL="https://nexus.mgmt.internal:8443/repository/pypi-internal/simple"
EFS_ID="fs-03be23c91310a0b60"
EFS_MOUNT_POINT="/mnt/cdefs"
EFS_BASE_DIR="/mnt/cdefs/results"  # Base directory for writing results

# Install EFS Utils
sudo apt-get update
sudo apt-get -y install git binutils
git clone https://gitlab.mgmt.internal/jdehart/efs-utils.git
cd efs-utils
sudo chmod +x build-deb.sh
./build-deb.sh
sudo apt-get -y install ./build/amazon-efs-utils*deb
cd ..

# Change the hostname
sudo hostnamectl set-hostname $HOSTNAME
echo "127.0.1.1 $HOSTNAME" | sudo tee -a /etc/hosts > /dev/null

# Update and install Scilab (not Scilab-CLI)
sudo apt-get update
sudo apt-get install -y scilab

# Install Python3 and pip
sudo apt-get install -y python3 python3-pip

# Install Flask using the specified internal repository
pip3 install Flask --index-url $INDEX_URL --trusted-host $(echo $INDEX_URL | awk -F/ '{print $3}')

# Flask application setup
FLASK_APP_DIR="$HOME/flask_scilab"
mkdir -p $FLASK_APP_DIR
cd $FLASK_APP_DIR

# Ensure the base directory for EFS results exists
sudo mkdir -p $EFS_BASE_DIR

# Create Flask app with updated endpoints and scilab-adv-cli
cat > app.py << 'EOF'
from flask import Flask, request, jsonify
import subprocess
import tempfile
import os

app = Flask(__name__)

def ensure_dir(file_path):
    directory = os.path.dirname(file_path)
    if not os.path.exists(directory):
        return False, "Directory does not exist: " + directory
    if not os.access(directory, os.W_OK):
        return False, "Directory is not writable: " + directory
    return True, ""

@app.route('/sci_instruct', methods=['POST'])
def sci_instruct():
    script = request.data.decode('utf-8')
    write_to_efs = request.args.get('write_to_efs', 'false').lower() == 'true'
    results_file_name = request.args.get('results_file_name', None)
    
    with tempfile.NamedTemporaryFile(delete=False, suffix='.sci') as tmp_file:
        tmp_file_path = tmp_file.name
        tmp_file.write(script.encode('utf-8'))
    
    result = subprocess.run(['scilab-adv-cli', '-f', tmp_file_path, '-nb', '-nwni', '-quit', '-noatomsautoload'], capture_output=True, text=True)
    os.unlink(tmp_file_path)
    
    if result.returncode == 0:
        if write_to_efs and results_file_name:
            efs_file_path = os.path.join(os.getenv('EFS_BASE_DIR', '/mnt/cdefs'), results_file_name)
            dir_ok, msg = ensure_dir(efs_file_path)
            if not dir_ok:
                return jsonify({'error': msg}), 400
            with open(efs_file_path, 'w') as f:
                f.write(result.stdout)
            return jsonify({'message': 'OK'}), 200
        else:
            return jsonify({'output': result.stdout}), 200
    else:
        return jsonify({'error': result.stderr}), 400

@app.route('/sci_script', methods=['POST'])
def sci_script():
    if 'file' not in request.files:
        return jsonify({'error': 'No file part'}), 400
    file = request.files['file']
    write_to_efs = request.args.get('write_to_efs', 'false').lower() == 'true'
    results_file_name = request.args.get('results_file_name', None)
    
    if file.filename == '':
        return jsonify({'error': 'No selected file'}), 400
    if file:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.sci') as tmp_file:
            file.save(tmp_file.name)
            execString = ['scilab-adv-cli', '-f', tmp_file.name, '-nb', '-nwni', '-quit', '-noatomsautoload']
            result = subprocess.run(execString, capture_output=True, text=True)
            os.unlink(tmp_file.name)
        
        if result.returncode == 0:
            if write_to_efs and results_file_name:
                efs_file_path = os.path.join(os.getenv('EFS_BASE_DIR', '/mnt/cdefs'), results_file_name)
                dir_ok, msg = ensure_dir(efs_file_path)
                if not dir_ok:
                    return jsonify({'error': msg}), 400
                with open(efs_file_path, 'w') as f:
                    f.write(result.stdout)
                return jsonify({'message': 'OK'}), 200
            else:
                return jsonify({'output': result.stdout}), 200
        else:
            return jsonify({'error': result.stderr}), 400

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0')
EOF

# Create systemd service file with EFS_BASE_DIR environment variable
SERVICE_FILE="/etc/systemd/system/flaskscilab.service"
sudo bash -c "cat > $SERVICE_FILE" << EOF
[Unit]
Description=Flask Scilab Service
After=network.target

[Service]
User=$USER
Group=$(id -gn $USER)
WorkingDirectory=$FLASK_APP_DIR
ExecStart=/usr/bin/python3 $FLASK_APP_DIR/app.py
Environment=EFS_BASE_DIR=$EFS_BASE_DIR

[Install]
WantedBy=multi-user.target
EOF

# Enable and start the service
sudo systemctl daemon-reload
sudo systemctl enable flaskscilab.service
sudo systemctl start flaskscilab.service

# Mount EFS Drive
sudo mkdir -p $EFS_MOUNT_POINT
echo "$EFS_ID:/ $EFS_MOUNT_POINT efs defaults,_netdev 0 0" | sudo tee -a /etc/fstab > /dev/null
sudo mount -a

echo "Installation, service setup, and EFS mount complete."

# Automated Testing Section
echo "Starting automated tests for Flask Scilab Service..."

# Define test variables
TEST_ENDPOINT="http://localhost:5000"
SCI_INSTRUCT_ENDPOINT="$TEST_ENDPOINT/sci_instruct"
SCI_SCRIPT_ENDPOINT="$TEST_ENDPOINT/sci_script"
TEST_SCRIPT_CONTENT="disp(5*5);"
TEST_FILE_NAME="test_script.sci"
TEST_RESULT_FILE_NAME="result_test.txt"

# Create a temporary Scilab script file for testing
echo "$TEST_SCRIPT_CONTENT" > "$TEST_FILE_NAME"

# Test 1: Direct execution result
echo "Testing direct execution result..."
TEST_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: text/plain" --data "$TEST_SCRIPT_CONTENT" "$SCI_INSTRUCT_ENDPOINT")
if [ "$TEST_RESPONSE" -eq 200 ]; then
    echo "Test 1: Direct execution result successful."
else
    echo "Test 1: Direct execution result failed."
    exit 1
fi

# Test 2: Execution result written to EFS
echo "Testing execution result written to EFS..."
TEST_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST -H "Content-Type: text/plain" --data "$TEST_SCRIPT_CONTENT" "$SCI_INSTRUCT_ENDPOINT?write_to_efs=true&results_file_name=$TEST_RESULT_FILE_NAME")
if [ "$TEST_RESPONSE" -eq 200 ]; then
    echo "Test 2: Execution result written to EFS successful."
else
    echo "Test 2: Execution result written to EFS failed."
    exit 1
fi

# Test 3: Upload Scilab script file and get result directly
echo "Testing upload Scilab script file and get result directly..."
TEST_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -F "file=@$TEST_FILE_NAME" "$SCI_SCRIPT_ENDPOINT")
if [ "$TEST_RESPONSE" -eq 200 ]; then
    echo "Test 3: Upload and execute Scilab script file successful."
else
    echo "Test 3: Upload and execute Scilab script file failed."
    exit 1
fi

# Test 4: Upload Scilab script file and write result to EFS
echo "Testing upload Scilab script file and write result to EFS..."
TEST_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -F "file=@$TEST_FILE_NAME" "$SCI_SCRIPT_ENDPOINT?write_to_efs=true&results_file_name=$TEST_RESULT_FILE_NAME")
if [ "$TEST_RESPONSE" -eq 200 ]; then
    echo "Test 4: Upload Scilab script file and write result to EFS successful."
else
    echo "Test 4: Upload Scilab script file and write result to EFS failed."
    exit 1
fi

# Cleanup test files
rm "$TEST_FILE_NAME"

echo "All automated tests completed successfully."
