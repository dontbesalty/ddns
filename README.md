# Cloudflare DDNS Updater Script

This script checks your current public IP address and updates a specified Cloudflare DNS record if the IP has changed. It can optionally send a notification via Pushover upon successful update.

## Features

*   Checks public IP using an external service (api.ipify.org by default).
*   Compares current IP with the last known IP stored locally (`~/.config/ddns/last_ip.txt`).
*   Updates a specified Cloudflare DNS record (A record by default) via the Cloudflare API if the IP has changed.
*   Loads configuration from a `.env` file in the same directory as the script.
*   Falls back to default placeholder values if `.env` is missing or variables are not set.
*   Optionally sends a success notification via Pushover.
*   Logs activity to a file (`~/Library/Logs/ddns_update.log` on macOS).

## Dependencies

*   `bash`: The script is written for bash.
*   `curl`: Used for making HTTP requests to the IP service and Cloudflare/Pushover APIs.
*   `jq`: Used for parsing JSON responses from the Cloudflare API.

## Configuration

Create a file named `.env` in the same directory as the `update_cloudflare_dns.sh` script. Add the following variables, replacing the placeholder values with your actual details:

```dotenv
# Cloudflare Settings
# Required: Your Cloudflare API Token (needs Zone:DNS:Edit permission for the target zone)
CF_API_TOKEN="YOUR_CLOUDFLARE_API_TOKEN"
# Required: Your Cloudflare Zone ID (find on the zone's Overview page)
CF_ZONE_ID="YOUR_ZONE_ID"
# Required: The full DNS record name to update (e.g., home.yourdomain.com)
RECORD_NAME="subdomain.example.com"
# Optional: DNS record type (defaults to "A" if unset)
# RECORD_TYPE="A"

# Pushover Notification Settings (Optional)
# Set to true or false to enable/disable Pushover (defaults to true if unset)
PUSHOVER_ENABLE=true
# Required if PUSHOVER_ENABLE=true: Your Pushover User Key
PUSHOVER_USER_KEY="YOUR_PUSHOVER_USER_KEY"
# Required if PUSHOVER_ENABLE=true: Your Pushover Application API Token
PUSHOVER_API_TOKEN="YOUR_PUSHOVER_API_TOKEN"
```

**Finding Cloudflare Details:**
*   **Zone ID:** Log in to Cloudflare, select your domain, and find the Zone ID on the right side of the "Overview" page.
*   **API Token:** Go to "My Profile" -> "API Tokens" -> "Create Token". Use the "Edit zone DNS" template, grant permissions for the specific zone you want to update, and copy the generated token.

**Finding Pushover Details:**
*   **User Key:** Log in to Pushover, your User Key is displayed on the dashboard.
*   **API Token:** Register an application on the Pushover site to get an API Token/Key for your script.

## Setup

1.  **Clone/Download:** Get the `update_cloudflare_dns.sh` script and place it in your desired directory.
2.  **Configure:** Create and populate the `.env` file in the same directory as described above.
3.  **Make Executable:** Open your terminal in the script's directory and run:
    ```bash
    chmod +x update_cloudflare_dns.sh
    ```

## Usage

Run the script directly from your terminal:

```bash
./update_cloudflare_dns.sh
```

Check the log file (`~/Library/Logs/ddns_update.log`) for detailed output.

## Scheduling (Example: Cron)

To run the script automatically (e.g., every 15 minutes), you can use `cron`.

1.  Edit your crontab: `crontab -e`
2.  Add a line like this, replacing `/path/to/script/` with the **absolute path** to the script's directory:

    ```cron
    */15 * * * * /path/to/script/update_cloudflare_dns.sh > /dev/null 2>&1
    ```
    *(This runs the script every 15 minutes and discards standard output/error, relying on the script's internal logging.)*

3.  Save and exit the editor. Make sure the path is correct and the script is executable by the user running the cron job.
