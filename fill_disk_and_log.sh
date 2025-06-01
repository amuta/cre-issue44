#!/bin/bash
# Minimal script to reproduce Postgres disk full and capture raw server logs.
# Requires docker-compose.yml in the same directory.

set -e # Exit script on any error

LOG_FILE="test.log"
SERVICE_NAME="postgres"
DB_USER="postgres" # Must match POSTGRES_USER in docker-compose.yml

# SQL designed to fill the tmpfs.
# repeat('a', 1000000) is approx 1MB. generate_series(1, 100) creaa\tes ~100MB of logical data.
SQL_FILL_DISK="CREATE TABLE IF NOT EXISTS fill_disk (data TEXT); INSERT INTO fill_disk (data) SELECT repeat('a', 1000000) FROM generate_series(1, 2000);"

# --- Script Execution ---

printf "Initializing and starting %s...\n" "$SERVICE_NAME"
docker-compose down -v 
rm -f "$LOG_FILE" # Remove old log file
docker-compose up -d "$SERVICE_NAME" # Start postgres in detached mode

printf "Waiting for %s to become healthy...\n" "$SERVICE_NAME"
# Loop until pg_isready (via docker-compose exec) succeeds
until docker-compose exec -T "$SERVICE_NAME" pg_isready -U "$DB_USER" -q; do
    sleep 0.5 # Check every half second
done
printf "%s is healthy.\n" "$SERVICE_NAME"

# Get container ID for raw log capture
CONTAINER_ID=$(docker-compose ps -q "$SERVICE_NAME")
if [ -z "$CONTAINER_ID" ]; then
    printf "Error: Could not retrieve container ID for %s.\n" "$SERVICE_NAME" >&2
    docker-compose logs "$SERVICE_NAME" # Output logs for debugging
    docker-compose down -v --remove-orphans --quiet # Cleanup
    exit 1
fi

printf "Capturing raw logs from container %s to %s...\n" "$CONTAINER_ID" "$LOG_FILE"
# Start background process to capture raw logs from the container
docker logs -n0 -f "$CONTAINER_ID" > "$LOG_FILE" 2>&1 &
LOG_PID=$!
disown "$LOG_PID" # Prevent SIGHUP if script terminal closes (though we kill it)
sleep 1          # Short pause for log stream to establish

printf "Executing SQL to fill the disk (errors are expected)...\n"
set +e # Temporarily disable exit on error for the psql command
docker-compose exec -T "$SERVICE_NAME" psql -U "$DB_USER" -d "$DB_USER" -c "$SQL_FILL_DISK"
PSQL_EXIT_CODE=$? # Capture psql exit code
set -e # Re-enable exit on error

# Provide feedback on psql execution
if [ $PSQL_EXIT_CODE -eq 0 ]; then
    printf "Warning: psql command completed successfully (exit code 0). Disk might not have filled as expected.\n" >&2
else
    printf "psql command exited with code %s (expected if server failed or disconnected due to disk full).\n" "$PSQL_EXIT_CODE"
fi

printf "Waiting a few seconds for all error messages to be logged...\n"
sleep 5 # Allow time for PANIC messages to be written to logs

printf "Stopping log capture (PID: %s)...\n" "$LOG_PID"
kill "$LOG_PID"
wait "$LOG_PID" 2>/dev/null || true # Wait for log process to terminate, suppress "Terminated" or "No such process" messages

printf "\n--- Simulation Complete ---\n"
printf "Raw PostgreSQL server logs should be in: %s\n" "$LOG_FILE"
printf "To clean up the Docker environment, run: docker-compose down -v\n"