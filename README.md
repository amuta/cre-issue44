# Minimal PostgreSQL Disk Saturation Test

This setup reproduces a PostgreSQL disk saturation failure (typically a PANIC) and saves the raw server logs to `test.log`.

## Files

1.  **`docker-compose.yml`**: Defines the PostgreSQL service with a small (20MB) `tmpfs` data volume and a healthcheck.
2.  **`fill_disk_and_log.sh`**: Script to automate the test:
    * Cleans up previous Docker environment.
    * Starts PostgreSQL.
    * Waits for it to be healthy.
    * Captures raw server logs to `test.log`.
    * Executes SQL to fill the disk.
    * Stops log capture.

## Instructions

1.  **Ensure Docker and Docker Compose are installed.**
2.  **Run the test:**
    ```bash
    ./fill_disk_and_log.sh
    ```
3.  **Inspect Logs:**
    After the script finishes, check `test.log`. You should find errors like "No space left on device" and "PANIC". The log lines will be the raw output from PostgreSQL (e.g., starting with `YYYY-MM-DD HH:MM:SS.mmm UTC [...]`).
4. **Run preq on the logs:**
