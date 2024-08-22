#!/bin/bash

# Check if Flask is installed
if ! python3 -c "import flask" &> /dev/null; then
    echo "Flask is not installed. Installing Flask..."
    sudo apt-get update
    sudo apt-get install -y python3-flask
else
    echo "Flask is already installed."
fi

# Define the port
PORT=8000

# Find the PID using ss and kill it
PID=$(ss -ltnp | grep ":$PORT" | awk '{print $6}' | cut -d',' -f2 | cut -d'=' -f2)

if [ ! -z "$PID" ]; then
    echo "Port $PORT is in use by process $PID. Killing the process..."
    kill -9 $PID
    echo "Killed the process using port $PORT."
fi

# Check if the server.py file exists, if not, create it
if [ ! -f server.py ]; then
    echo "server.py not found. Creating server.py..."
    cat <<EOL > server.py
from flask import Flask, request, render_template_string, redirect, url_for, make_response
import os
import crypt
import subprocess

app = Flask(__name__)

UPLOAD_FOLDER = '/media'

# Helper Functions
def check_pi_password(password):
    """Check if the given password is correct for the 'pi' user."""
    shadow_file = '/etc/shadow'
    with open(shadow_file) as f:
        for line in f:
            if line.startswith('pi:'):
                parts = line.split(':')
                stored_hash = parts[1]
                break

    salt = stored_hash[:stored_hash.rfind('$')+1]
    hashed_password = crypt.crypt(password, salt)

    return hashed_password == stored_hash

def get_storage_info():
    storage_info = run_df_command()
    filtered_lines, mounted_dirs = parse_storage_info(storage_info)
    formatted_storage_info = format_storage_info(filtered_lines)
    return formatted_storage_info, mounted_dirs

def run_df_command():
    result = subprocess.run(['df', '-h'], stdout=subprocess.PIPE)
    return result.stdout.decode('utf-8')

def parse_storage_info(storage_info):
    mounts_to_show = ['/media/usb1', '/media/usb2', '/media/nfsg', '/media/nfsl']
    filtered_lines = []
    mounted_dirs = []
    
    for line in storage_info.splitlines():
        for mount in mounts_to_show:
            if line.endswith(mount):
                drive_name = mount.split('/')[-1]
                fields = line.split()
                selected_fields = [drive_name, fields[1], fields[2], fields[4]]
                filtered_lines.append(selected_fields)
                mounted_dirs.append(drive_name)
                break

    if not filtered_lines:
        for line in storage_info.splitlines():
            if line.endswith('/'):
                fields = line.split()
                selected_fields = ['sd', fields[1], fields[2], fields[4]]
                filtered_lines.append(selected_fields)
                mounted_dirs.append('sd')

    return filtered_lines, mounted_dirs

def format_storage_info(filtered_lines):
    formatted_lines = ["<tr><th>Drive</th><th>Total Space</th><th>Used</th><th>Use%</th></tr>"]
    for fields in filtered_lines:
        formatted_lines.append(f"<tr><td>{'</td><td>'.join(fields)}</td></tr>")
    return '<table>' + ''.join(formatted_lines) + '</table>'

def handle_file_upload(subpath):
    full_path = os.path.join(UPLOAD_FOLDER, subpath)
    for file in request.files.getlist('file'):
        file.save(os.path.join(full_path, file.filename))
        os.chmod(os.path.join(full_path, file.filename), 0o777)

def render_directory_view(subpath, storage_info, mounted_dirs):
    full_path = os.path.join(UPLOAD_FOLDER, subpath)
    if subpath == '':
        files = [f for f in sorted(os.listdir(full_path)) if f in mounted_dirs]
        if 'sd' not in files and 'sd' in mounted_dirs:
            files.append('sd')
        show_upload = False
    else:
        files = sorted(os.listdir(full_path))
        show_upload = True

    parent_path = os.path.dirname(subpath) if subpath else ''
    
    return render_template_string('''
        <html>
        <head>
            <title>RGB-Pi OS4 Tools</title>
            <style>
                body {
                    font-family: Arial, sans-serif;
                    background-color: #f4f4f4;
                    color: #333;
                    margin: 0;
                    padding: 0;
                    display: flex;
                    flex-direction: column;
                    min-height: 100vh;
                }
                .container {
                    max-width: 900px;
                    margin: 20px auto;
                    padding: 20px;
                    background-color: #fff;
                    box-shadow: 0 0 10px rgba(0, 0, 0, 0.1);
                    border-radius: 8px;
                }
                h1, h3 {
                    color: #0066cc;
                }
                table {
                    width: 100%;
                    border-collapse: collapse;
                    margin-bottom: 20px;
                }
                th, td {
                    padding: 8px 12px;
                    border: 1px solid #ddd;
                    text-align: left;
                }
                th {
                    background-color: #f2f2f2;
                }
                ul {
                    list-style-type: none;
                    padding: 0;
                }
                li {
                    margin: 5px 0;
                }
                a {
                    color: #0066cc;
                    text-decoration: none;
                }
                a:hover {
                    text-decoration: underline;
                }
                button {
                    background-color: #0066cc;
                    color: white;
                    padding: 10px 20px;
                    border: none;
                    border-radius: 5px;
                    cursor: pointer;
                }
                button:hover {
                    background-color: #004c99;
                }
                footer {
                    margin-top: auto;
                    padding: 10px;
                    background-color: #333;
                    color: white;
                    text-align: center;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <button onclick="location.href='{{ url_for('homepage') }}'" style="margin-right: 10px;">Home</button>
                <h1>ROM Transfer Tool</h1>
                <p style="font-size: 0.9em; color: #666; margin-top: 5px;">
                    Select files or drag and drop them into this window to upload
                </p>
                <div>{{ storage_info|safe }}</div>

                {% if show_upload %}
                <form method="POST" enctype="multipart/form-data" id="uploadForm" style="display:inline;">
                    <input type="file" name="file" id="fileInput" multiple onchange="updateUploadButtonState()">
                    <input type="submit" id="uploadButton" value="Upload" disabled>
                </form>
                {% endif %}

                {% if subpath != '' %}
                    <div style="margin-top: 20px;">
                        <a href="{{ url_for('browse', subpath=parent_path) }}" id="backLink">..</a>
                    </div>
                {% endif %}

                <ul id="folderList">
                    {% for file in files %}
                        <li>
                            <a href="{{ url_for('browse', subpath=subpath + '/' + file) }}">{{ file }}</a>
                        </li>
                    {% endfor %}
                </ul>

                <div id="uploadingMessage" style="display:none;">
                    <p>Uploading files... Please wait.</p>
                    <div id="fileList"></div>
                    <progress id="progressBar" value="0" max="100" style="width: 100%;"></progress>
                    <a href="#" id="stopUpload">Stop</a>
                </div>
            </div>

            <footer>
                Created by Kev | <a href="https://github.com/forkymcforkface/" target="_blank" style="color: #fff;">GitHub</a>
            </footer>

            <script>
                let xhr = null;

                function updateUploadButtonState() {
                    const fileInput = document.getElementById('fileInput');
                    const uploadButton = document.getElementById('uploadButton');
                    const fileList = document.getElementById('fileList');
                    fileList.innerHTML = '<ul>' + Array.from(fileInput.files).map(file => '<li>' + file.name + '</li>').join('') + '</ul>';
                    uploadButton.disabled = fileInput.files.length === 0;
                }

                document.getElementById('uploadForm').onsubmit = function(event) {
                    event.preventDefault();
                    const formData = new FormData(this);
                    xhr = new XMLHttpRequest();

                    xhr.upload.addEventListener('progress', function(e) {
                        const percent = e.lengthComputable ? (e.loaded / e.total) * 100 : 0;
                        document.getElementById('progressBar').value = percent.toFixed(2);
                    });

                    xhr.addEventListener('load', function() {
                        if (xhr.status === 200) {
                            window.location.reload();
                        } else {
                            alert('Upload failed.');
                        }
                    });

                    xhr.open('POST', window.location.href, true);
                    xhr.send(formData);

                    document.getElementById('uploadForm').style.display = 'none';
                    document.getElementById('folderList').style.display = 'none';
                    document.getElementById('uploadingMessage').style.display = 'block';
                    document.getElementById('backLink').style.display = 'none';
                };

                document.getElementById('stopUpload').onclick = function() {
                    if (xhr) {
                        xhr.abort();
                        alert('Upload stopped.');
                        window.location.reload();
                    }
                };

                document.addEventListener('dragover', function(event) {
                    event.preventDefault();
                });

                document.addEventListener('drop', function(event) {
                    event.preventDefault();
                    const files = event.dataTransfer.files;
                    const fileInput = document.getElementById('fileInput');

                    fileInput.files = files;

                    updateUploadButtonState();
                    document.getElementById('uploadForm').submit();
                });
            </script>
        </body>
        </html>
    ''', subpath=subpath, files=files, parent_path=parent_path, storage_info=storage_info, show_upload=show_upload)

@app.route('/')
def homepage():
    if not request.cookies.get('authenticated'):
        return redirect(url_for('login'))
    return render_template_string('''
        <html>
        <head>
            <title>RGB-Pi OS4 Tools</title>
            <style>
                body {
                    font-family: Arial, sans-serif;
                    background-color: #f4f4f4;
                    color: #333;
                    margin: 0;
                    padding: 0;
                    display: flex;
                    flex-direction: column;
                    min-height: 100vh;
                }
                .container {
                    max-width: 900px;
                    margin: 20px auto;
                    padding: 20px;
                    background-color: #fff;
                    box-shadow: 0 0 10px rgba(0, 0, 0, 0.1);
                    border-radius: 8px;
                }
                h1 {
                    color: #0066cc;
                }
                button {
                    background-color: #0066cc;
                    color: white;
                    padding: 10px 20px;
                    border: none;
                    border-radius: 5px;
                    cursor: pointer;
                    margin: 10px;
                }
                button:hover {
                    background-color: #004c99;
                }
                footer {
                    margin-top: auto;
                    padding: 10px;
                    background-color: #333;
                    color: white;
                    text-align: center;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>Unofficial RGB-Pi OS4 Tools</h1>
                <button onclick="location.href='{{ url_for('browse', subpath='') }}'">Transfer ROMs</button>
                <button onclick="location.href='{{ url_for('options') }}'">Options</button>
            </div>
            <footer>
                Created by Kev | <a href="https://github.com/forkymcforkface/" target="_blank" style="color: #fff;">GitHub</a>
            </footer>
        </body>
        </html>
    ''')

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        password = request.form['password']
        if check_pi_password(password):
            response = make_response(redirect(url_for('homepage')))
            response.set_cookie('authenticated', 'true')
            return response
        else:
            return render_template_string('''
                <html>
                <head>
                    <title>Login</title>
                    <style>
                        body {
                            font-family: Arial, sans-serif;
                            background-color: #f4f4f4;
                            color: #333;
                            margin: 0;
                            padding: 0;
                            display: flex;
                            flex-direction: column;
                            min-height: 100vh;
                        }
                        .container {
                            max-width: 400px;
                            margin: 50px auto;
                            padding: 20px;
                            background-color: #fff;
                            box-shadow: 0 0 10px rgba(0, 0, 0, 0.1);
                            border-radius: 8px;
                        }
                        h2 {
                            color: #0066cc;
                            margin-bottom: 20px;
                        }
                        input[type="password"] {
                            width: calc(100% - 22px);
                            padding: 10px;
                            margin-bottom: 10px;
                            border: 1px solid #ccc;
                            border-radius: 5px;
                        }
                        input[type="submit"] {
                            width: 100%;
                            padding: 10px;
                            background-color: #0066cc;
                            color: white;
                            border: none;
                            border-radius: 5px;
                            cursor: pointer;
                        }
                        input[type="submit"]:hover {
                            background-color: #004c99;
                        }
                        p {
                            color: red;
                        }
                    </style>
                </head>
                <body>
                    <div class="container">
                        <h2>Login</h2>
                        <p>Incorrect password, please try again.</p>
                        <form method="POST">
                            <input type="password" name="password" placeholder="Enter Pi password" required>
                            <input type="submit" value="Login">
                        </form>
                    </div>
                </body>
                </html>
            ''')
    return render_template_string('''
        <html>
        <head>
            <title>Login</title>
            <style>
                body {
                    font-family: Arial, sans-serif;
                    background-color: #f4f4f4;
                    color: #333;
                    margin: 0;
                    padding: 0;
                    display: flex;
                    flex-direction: column;
                    min-height: 100vh;
                }
                .container {
                    max-width: 400px;
                    margin: 50px auto;
                    padding: 20px;
                    background-color: #fff;
                    box-shadow: 0 0 10px rgba(0, 0, 0, 0.1);
                    border-radius: 8px;
                }
                h2 {
                    color: #0066cc;
                    margin-bottom: 20px;
                }
                input[type="password"] {
                    width: calc(100% - 22px);
                    padding: 10px;
                    margin-bottom: 10px;
                    border: 1px solid #ccc;
                    border-radius: 5px;
                }
                input[type="submit"] {
                    width: 100%;
                    padding: 10px;
                    background-color: #0066cc;
                    color: white;
                    border: none;
                    border-radius: 5px;
                    cursor: pointer;
                }
                input[type="submit"]:hover {
                    background-color: #004c99;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <h2>Login</h2>
                <form method="POST">
                    <input type="password" name="password" placeholder="Enter Pi password" required>
                    <input type="submit" value="Login">
                </form>
            </div>
        </body>
        </html>
    ''')

@app.route('/logout')
def logout():
    response = make_response(redirect(url_for('login')))
    response.set_cookie('authenticated', '', expires=0)
    return response

@app.route('/options')
def options():
    if not request.cookies.get('authenticated'):
        return redirect(url_for('login'))
    return render_template_string('''
        <html>
        <head>
            <title>Options</title>
            <style>
                body {
                    font-family: Arial, sans-serif;
                    background-color: #f4f4f4;
                    color: #333;
                    margin: 0;
                    padding: 0;
                    display: flex;
                    flex-direction: column;
                    min-height: 100vh;
                }
                .container {
                    max-width: 600px;
                    margin: 50px auto;
                    padding: 20px;
                    background-color: #fff;
                    box-shadow: 0 0 10px rgba(0, 0, 0, 0.1);
                    border-radius: 8px;
                }
                h2 {
                    color: #0066cc;
                    margin-bottom: 20px;
                }
                button {
                    background-color: #0066cc;
                    color: white;
                    padding: 10px 20px;
                    border: none;
                    border-radius: 5px;
                    cursor: pointer;
                    margin: 10px;
                }
                button:hover {
                    background-color: #004c99;
                }
                footer {
                    margin-top: auto;
                    padding: 10px;
                    background-color: #333;
                    color: white;
                    text-align: center;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <h2>Options</h2>
                <p>This enables the file transfer tool to always be running. (not implemented yet)</p>
                <button onclick="install_service()">Install File Transfer Service</button>
                <button onclick="uninstall_service()">Uninstall File Transfer Service</button>
                <button onclick="location.href='{{ url_for('homepage') }}'">Back</button>
                <button onclick="location.href='{{ url_for('logout') }}'">Logout</button>
            </div>
            <footer>
                Created by Kev | <a href="https://github.com/forkymcforkface/" target="_blank" style="color: #fff;">GitHub</a>
            </footer>

            <script>
                function install_service() {
                    alert('File Transfer Service Installed.');
                    // Add your installation code here
                }

                function uninstall_service() {
                    alert('File Transfer Service Uninstalled.');
                    // Add your uninstallation code here
                }
            </script>
        </body>
        </html>
    ''')

@app.route('/browse/', defaults={'subpath': ''})
@app.route('/browse/<path:subpath>', methods=['GET', 'POST'])
def browse(subpath):
    if not request.cookies.get('authenticated'):
        return redirect(url_for('login'))

    if request.method == 'POST':
        handle_file_upload(subpath)
        return redirect(url_for('browse', subpath=subpath))

    storage_info, mounted_dirs = get_storage_info()
    return render_directory_view(subpath, storage_info, mounted_dirs)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000)
EOL
    echo "server.py created."
fi

# Start the Flask server
echo "Starting the server..."
python3 server.py &
