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