# CpuLimit

A bash script and systemd service that dynamically adjusts CPU usage of processes to maintain a specified CPU threshold. This tool helps prevent resource exhaustion on single-core or multi-core Linux systems by limiting the CPU consumption of high-usage processes in real-time.

## Features

- Automatically monitors total CPU usage.
- Dynamically applies CPU limits to active processes.
- Customizable target CPU usage threshold (default: 50%).
- Runs as a background service using `systemd`.
- Uses `cpulimit` to restrict process CPU usage.

## Requirements

- Linux system with `systemd`.
- `cpulimit` installed.

## Installation

### Step 1: Install `cpulimit`

```bash
sudo apt update
sudo apt install cpulimit
```

### Step 2: Clone the Repository

```bash
git clone https://github.com/ChalanaGimhanaX/CpuLimit.git
cd CpuLimit
```

### Step 3: Move the Script to `/usr/local/bin`

```bash
sudo mv dynamic_cpu_limiter.sh /usr/local/bin/
sudo chmod +x /usr/local/bin/dynamic_cpu_limiter.sh
```

### Step 4: Setup the Systemd Service

```bash
sudo cp dynamic_cpu_limiter.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable dynamic_cpu_limiter.service
sudo systemctl start dynamic_cpu_limiter.service
```

### Step 5: Verify the Service Status

```bash
sudo systemctl status dynamic_cpu_limiter.service
```

## Usage

- **Check CPU usage and limits in real-time:**

  ```bash
  sudo journalctl -u dynamic_cpu_limiter.service -f
  ```

- **Manually stop the service:**

  ```bash
  sudo systemctl stop dynamic_cpu_limiter.service
  ```

- **Restart the service:**

  ```bash
  sudo systemctl restart dynamic_cpu_limiter.service
  ```

## Configuration

To change the target CPU usage threshold, modify the following line in the `dynamic_cpu_limiter.sh` script:

```bash
TARGET_CPU_USAGE=50
```

Set the desired percentage value (e.g., `TARGET_CPU_USAGE=75` for a 75% limit).

## Troubleshooting

1. **"sudo: cpulimit: command not found" Error:**
   Ensure `cpulimit` is installed and available in your `PATH`.

   ```bash
   sudo apt install cpulimit
   ```

2. **Service not starting:**
   Check the logs for errors:

   ```bash
   sudo journalctl -u dynamic_cpu_limiter.service
   ```

## Contributing

Feel free to submit issues or pull requests to improve this project. Contributions are welcome!

## License

This project is licensed under the MIT License.
