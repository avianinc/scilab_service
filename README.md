# Scilab Flask Server with EFS Support

This repository contains a Bash script for automating the setup of a Flask application designed to execute Scilab scripts. It includes functionality for writing results directly to an Elastic File System (EFS), making it suitable for scalable and distributed computing environments.

## Overview

The script automates the following tasks:
- Installs necessary packages including Scilab (not CLI version) and Python3 with Flask.
- Configures a Flask application to execute Scilab scripts either directly or via uploaded files.
- Sets up the application to run as a systemd service for reliability.
- Supports writing execution results to a specified directory within an AWS EFS mount.

## Requirements

- Ubuntu Linux (Tested on Ubuntu 20.04)
- Internet connection for package downloads
- Sudo privileges for package installation and service setup
- AWS EFS mounted on the host system

## Installation

1. Ensure you have sudo privileges on your Ubuntu system.
2. Clone this repository or download the `install_scilab_flask_efs.sh` script.
3. Make the script executable:
   ```bash
   chmod +x install_scilab_flask_efs.sh
   ```
4. Run the script:
   ```bash
   ./install_scilab_flask_efs.sh
   ```

## Usage

The Flask application provides two endpoints:

- `/sci_instruct`: Accepts raw Scilab script content via POST request and executes it.
- `/sci_script`: Accepts a Scilab script file via POST request for execution.

### Example Calls

- Execute Scilab instruction and get result directly:
  ```bash
  curl -X POST -H "Content-Type: text/plain" --data "disp(5*5);" http://localhost:5000/sci_instruct
  ```

- Execute Scilab instruction and write result to EFS:
  ```bash
  curl -X POST -H "Content-Type: text/plain" --data "disp(5*5);" "http://localhost:5000/sci_instruct?write_to_efs=true&results_file_name=result1.txt"
  ```

- Upload Scilab script file and get result directly:
  ```bash
  curl -s -o response.txt -w "%{http_code}" -F "file=@test_script.sci" http://localhost:5000/sci_script
  ```

- Upload Scilab script file and write result to EFS:
  ```bash
  curl -s -o response.txt -w "%{http_code}" -F "file=@test_script.sci" "http://localhost:5000/sci_script?write_to_efs=true&results_file_name=result2.txt"
  ```

## Additional Notes

- Ensure your AWS EFS is correctly mounted on your host system at the specified mount point before running the script.
- The script sets up the Flask application to run as a systemd service named `flaskscilab.service`. You can use `systemctl` to manage the service (e.g., start, stop, restart).
- Modify the script as needed to accommodate different environments or specific requirements.

## Contributing

Contributions to improve the script or address issues are welcome. Please feel free to submit pull requests or open issues in this repository.
