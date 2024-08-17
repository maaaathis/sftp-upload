# SFTP Upload GitHub Action

> Use this GitHub Action to deploy your files to a server.

## Inputs

| Name                | Required | Default | Description                                                                                                        |
|---------------------|----------|---------|--------------------------------------------------------------------------------------------------------------------|
| `username`          | Yes      |         | SSH username                                                                                                       |
| `server`            | Yes      |         | Remote host (server IP or hostname)                                                                                |
| `port`              | Yes      | `22`    | Remote host port (default is 22)                                                                                   |
| `ssh_private_key`   | No       |         | SSH private key. Copy the contents of your private key file (e.g., `id_rsa`) and add it as a secret in your repository settings. |
| `local_path`        | Yes      | `./*`   | Local path of your project files to be uploaded. For a single file, use `./myfile`. For a directory, use `./static/*`. Default is `./*` (uploads all files in your repository). |
| `remote_path`       | Yes      |         | Remote path where files will be uploaded.                                                                          |
| `sftp_only`         | No       | `false` | Set to `true` if the remote host only accepts SFTP connections. Note: If set to `true`, the remote directory will not be created automatically. |
| `sftpArgs`          | No       |         | Additional SFTP arguments. For example, `-o ConnectTimeout=5`                                                      |
| `delete_remote_files` | No     | `false` | Set to `true` to delete all files in the remote path before uploading. **Use with caution.**                       |
| `password`          | No       |         | SSH password. If a password is set, the SSH private key will be ignored.                                           |

> **Warning**
>
> Use `delete_remote_files` with caution, as it will delete the entire remote directory and all files within it.

## Usage Examples

### Example 1: Basic SFTP Deployment Using SSH Private Key

```yaml
on: [push]

jobs:
  deploy_job:
    runs-on: ubuntu-latest
    name: Deploy Files
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Deploy Files via SFTP
        uses: maaaathis/sftp-upload@v1
        with:
          username: 'root'
          server: 'your-server-ip'
          ssh_private_key: ${{ secrets.SSH_PRIVATE_KEY }}
          local_path: './static/*'
          remote_path: '/var/www/app'
          sftpArgs: '-o ConnectTimeout=5'
```

### Example 2: SFTP Deployment with Password Authentication

```yaml
on: [push]

jobs:
  deploy_job:
    runs-on: ubuntu-latest
    name: Deploy Files
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Deploy Files via SFTP
        uses: maaaathis/sftp-upload@v1
        with:
          username: ${{ secrets.FTP_USERNAME }}
          server: ${{ secrets.FTP_SERVER }}
          port: ${{ secrets.FTP_PORT }}
          local_path: './static/*'
          remote_path: '/var/www/app'
          sftp_only: true
          password: ${{ secrets.FTP_PASSWORD }}
```

### Example 3: Deploy a React App

```yaml
on: [push]

jobs:
  deploy_job:
    runs-on: ubuntu-latest
    name: Build and Deploy
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install Dependencies
        run: yarn

      - name: Build React App
        run: yarn build

      - name: Deploy Build to Server
        uses: maaaathis/sftp-upload@v1
        with:
          username: 'root'
          server: ${{ secrets.SERVER_IP }}
          ssh_private_key: ${{ secrets.SSH_PRIVATE_KEY }}
          local_path: './build/*'
          remote_path: '/var/www/react-app'
          sftpArgs: '-o ConnectTimeout=5'
```

## Note on SSH Key Format

If you're using the Ed25519 algorithm to generate an SSH key pair, make sure to include the blank line at the end of the private key when adding it as a secret in your repository. Omitting this line may cause an `invalid format` or `error in libcrypto` error.
