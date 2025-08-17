- Service user home resolution and permissions
  - Use getent passwd to resolve the actual home (SERVICE_HOME) instead of assuming /home/$SERVICE_USER.
  - Create runtime/config directories as the service user and fix ownership.
  - Set Environment="HOME=$SERVICE_HOME" in the unit file.
  - Example:
    ```bash
    if ! id -u "$SERVICE_USER" >/dev/null 2>&1; then
      print_error "User $SERVICE_USER does not exist"; exit 1
    fi
    SERVICE_HOME="$(getent passwd "$SERVICE_USER" | cut -d: -f6)"
    [ -d "$SERVICE_HOME" ] || { print_error "Home not found for $SERVICE_USER"; exit 1; }
    sudo -u "$SERVICE_USER" mkdir -p "$SERVICE_HOME/.cui"
    sudo chown -R "$SERVICE_USER:$SERVICE_USER" "$SERVICE_HOME/.cui"
    ```

- nvm and Node detection for the service user
  - Probe "$SERVICE_HOME/.nvm/versions/node" for Node versions owned by the service user.
  - Fall back to the system Node if nvm is unavailable/inaccessible.

- Unit file naming and instances
  - Choose a clear approach:
    - Template unit: cui@.service and enable as cui@USERNAME.
    - Single instance: cui.service if only one instance is expected.

- Validate and sanitize user input
  - Ensure SERVICE_PORT is an integer within 1–65535; abort with a clear error on invalid input.

- Build prerequisites and artifacts
  - If node_modules is missing, prompt to run npm ci (or exit with guidance).
  - Ensure dist/server.js exists after build; abort with a clear message if not.

- Elevation and command safety
  - Prompt for sudo early with sudo -v to avoid mid-script password prompts.
  - Quote paths and derive Node binary/dir safely:
    ```bash
    NODE_BIN="$(command -v node)"
    NODE_DIR="$(dirname "$NODE_BIN")"
    ```

- Systemd unit hardening and operability
  - Add SyslogIdentifier=cui for clearer journald logs.
  - Consider:
    - NoNewPrivileges=true
    - PrivateTmp=true
    - ProtectSystem=full
    - ProtectHome=true
    - RestrictSUIDSGID=true
    - Restart=on-failure
    - RestartSec=5s
  - Prefer default KillMode=control-group unless a different behavior is required.

- Consistent environment handling
  - Since ExecStart uses an absolute Node path, PATH mainly affects child processes; ensure it includes the chosen Node dir only if needed.

- User experience polish
  - When enabling the service, print the exact systemctl commands based on the chosen naming scheme (template vs single unit).
  - Echo the resolved ExecStart, Service user, HOME, and WorkingDirectory before writing the unit and confirm with the user.
