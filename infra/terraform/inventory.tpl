[app_servers]
app-server ansible_host=${server_ip} ansible_user=${ssh_user} ansible_ssh_private_key_file=${ssh_key_path}

[app_servers:vars]
ansible_python_interpreter=/usr/bin/python3
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'