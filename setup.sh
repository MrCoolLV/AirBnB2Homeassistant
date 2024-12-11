#!/bin/bash
# Ivan Gonzalez @ ivanjr@gonzalez.lv

# Update and upgrade the system
echo "Updating system..."
sudo apt update && sudo apt upgrade -y

# Install required system dependencies
echo "Installing system dependencies..."
sudo apt install -y python3 python3-pip python3-venv curl git

# Install additional libraries
echo "Installing additional libraries..."
sudo apt install -y libffi-dev libssl-dev build-essential

# Create a project directory
echo "Setting up project directory..."
PROJECT_DIR="/opt/airbnb-home-automation"
sudo mkdir -p $PROJECT_DIR
sudo chown $USER:$USER $PROJECT_DIR

# Navigate to the project directory
cd $PROJECT_DIR

# Set up Python virtual environment
echo "Setting up Python virtual environment..."
python3 -m venv venv
source venv/bin/activate

# Install required Python packages
echo "Installing Python packages..."
pip install flask requests icalendar pytz

# Create the Flask app script
echo "Creating Flask app script..."
cat <<EOL > app.py
from flask import Flask, request, jsonify
from icalendar import Calendar
import requests
import datetime
import pytz
import os

# Configuration
AIRBNB_ICAL_URL = "YOUR_AIRBNB_ICAL_URL"  # Replace with your Airbnb iCal URL
HOME_ASSISTANT_URL = "http://YOUR_HOME_ASSISTANT_URL:8123/api"  # Replace with your Home Assistant URL
HA_TOKEN = "YOUR_HOME_ASSISTANT_LONG_LIVED_TOKEN"  # Replace with your HA token

# Flask app setup
app = Flask(__name__)

@app.route("/update-home", methods=["POST"])
def update_home():
    try:
        response = requests.get(AIRBNB_ICAL_URL)
        response.raise_for_status()
        gcal = Calendar.from_ical(response.text)

        now = datetime.datetime.now(pytz.utc)
        upcoming_events = []

        for component in gcal.walk():
            if component.name == "VEVENT":
                start = component.get("DTSTART").dt
                end = component.get("DTEND").dt
                if start > now:
                    upcoming_events.append({"start": start, "end": end})

        if upcoming_events:
            booking = upcoming_events[0]
            adjust_home_on_booking(booking)
            return jsonify({"message": "Home adjusted for upcoming booking.", "booking": booking}), 200
        else:
            reset_home()
            return jsonify({"message": "No upcoming bookings. Home reset to default state."}), 200

    except Exception as e:
        return jsonify({"error": str(e)}), 500

def adjust_home_on_booking(booking):
    try:
        set_light("on")
        set_temperature(72)
    except Exception as e:
        print(f"Error adjusting home: {e}")

def reset_home():
    try:
        set_light("off")
        set_temperature(78)
    except Exception as e:
        print(f"Error resetting home: {e}")

def set_light(state):
    url = f"{HOME_ASSISTANT_URL}/services/light/turn_{state}"
    headers = {"Authorization": f"Bearer {HA_TOKEN}", "Content-Type": "application/json"}
    data = {"entity_id": "light.living_room"}  # Replace with your actual entity ID
    response = requests.post(url, headers=headers, json=data)
    response.raise_for_status()

def set_temperature(temp):
    url = f"{HOME_ASSISTANT_URL}/services/climate/set_temperature"
    headers = {"Authorization": f"Bearer {HA_TOKEN}", "Content-Type": "application/json"}
    data = {"entity_id": "climate.thermostat", "temperature": temp}
    response = requests.post(url, headers=headers, json=data)
    response.raise_for_status()

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
EOL

# Make the app executable
echo "Setting script permissions..."
chmod +x app.py

# Create a systemd service to run the Flask app
echo "Creating systemd service..."
cat <<EOL | sudo tee /etc/systemd/system/airbnb-home-automation.service
[Unit]
Description=Airbnb Home Automation Flask App
After=network.target

[Service]
User=$USER
WorkingDirectory=$PROJECT_DIR
Environment="PATH=$PROJECT_DIR/venv/bin"
ExecStart=$PROJECT_DIR/venv/bin/python app.py

[Install]
WantedBy=multi-user.target
EOL

# Reload systemd and enable the service
echo "Enabling and starting the service..."
sudo systemctl daemon-reload
sudo systemctl enable airbnb-home-automation.service
sudo systemctl start airbnb-home-automation.service

# Print success message
echo "Installation complete. The Flask app is now running as a service."
echo "Access it via http://<YOUR_SERVER_IP>:5000/update-home"
