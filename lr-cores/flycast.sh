#!/bin/bash

clear

confirm_proceed() {
  echo -n "This process can take 30 mins on a Pi5, and 2 hrs+ on a Pi4. Do you want to proceed? (y/n) "
  read -r -s -n 1 response
  echo
  if [[ "$response" != "y" && "$response" != "Y" ]]; then
    echo "Process aborted by the user."
    exit 0
  fi
}

cleanup() {
  echo -e "\nCleaning up swap file..."
  sudo swapoff /media/usb1/swapfile 2>/dev/null || true
  sudo rm /media/usb1/swapfile 2>/dev/null || true
  echo "Cleanup complete."
}

trap cleanup EXIT

confirm_proceed

# Check if cmake and curl are installed
if ! command -v cmake &> /dev/null; then
  echo "CMake not found. Installing CMake..."
  sudo apt-get update -y > /dev/null 2>&1
  sudo apt-get install -y cmake > /dev/null 2>&1
  echo "CMake installation complete."
fi

if ! dpkg -s libcurl4-openssl-dev &> /dev/null; then
  echo "CURL development libraries not found. Installing CURL..."
  sudo apt-get install -y libcurl4-openssl-dev > /dev/null 2>&1
  echo "CURL installation complete."
fi

required_space=2
available_space=$(df --output=avail -BG /media/usb1 | tail -1 | tr -d 'G ')

if [ "$available_space" -lt "$required_space" ]; then
  echo "Error: Not enough free space on /media/usb1. At least 2GB is required."
  exit 1
fi

start_time=$(date +%s)

log_file="/media/usb1/flycast_build.log"
echo "Build log will be saved to: $log_file"

cd /media/usb1

# Check if Flycast has already been cloned
if [ ! -d "flycast" ]; then
  echo "Cloning Flycast repository..."
  git clone https://github.com/flyinghead/flycast.git > /dev/null 2>&1
fi

cd flycast

# Update submodules
echo "Updating submodules..."
git submodule update --init --recursive > /dev/null 2>&1

# Restart the swap if it exists
if [ -f "/media/usb1/swapfile" ]; then
  echo "Reusing existing swap file..."
  sudo swapoff /media/usb1/swapfile 2>/dev/null || true
  sudo swapon /media/usb1/swapfile > /dev/null 2>&1
else
  echo "Creating swap file..."
  sudo dd if=/dev/zero of=/media/usb1/swapfile bs=1G count=2 > /dev/null 2>&1
  sudo chmod 0777 /media/usb1/swapfile
  sudo mkswap /media/usb1/swapfile > /dev/null 2>&1
  sudo swapon /media/usb1/swapfile > /dev/null 2>&1
fi

monitor_usage() {
  while true; do
    cpu_usage=$(top -bn2 -d 0.01 | grep "Cpu(s)" | tail -n 1 | awk '{printf("%d", $2 + $4)}')
    mem_usage=$(free | grep Mem | awk '{printf("%d", $3/$2 * 100)}')
    swap_usage=$(free | grep Swap | awk '{printf("%d", $3/$2 * 100)}')
    echo -ne "\r\033[KCPU Usage: ${cpu_usage}% | Memory Usage: ${mem_usage}% | Swap Usage: ${swap_usage}%"
    sleep 5
  done
}

monitor_usage &

monitor_pid=$!

# Build and compile Flycast
echo "Building Flycast..."
mkdir -p build
cd build
cmake .. -DLIBRETRO=ON -DUSE_GLES=ON > "$log_file" 2>&1
make -j5 >> "$log_file" 2>&1

kill $monitor_pid
wait $monitor_pid 2>/dev/null

echo -ne "\r\033[K"

flycast_libretro_file=$(find . -name "flycast_libretro.so")

if [ -n "$flycast_libretro_file" ]; then
  if [ ! -f /opt/retroarch/cores/flycast_libretro.so.bak ]; then
    sudo mv /opt/retroarch/cores/flycast_libretro.so /opt/retroarch/cores/flycast_libretro.so.bak
  fi

  sudo cp "$flycast_libretro_file" /opt/retroarch/cores/flycast_libretro.so

  sync

  # Create the compiled directory if it doesn't exist
  if [ ! -d "/media/usb1/compiled" ]; then
    mkdir /media/usb1/compiled
  fi

  echo "Compressing flycast_libretro.so to flycast_libretro.7z..."
  7z a /media/usb1/compiled/flycast_libretro.7z "$flycast_libretro_file" > /dev/null 2>&1

  cd /media/usb1
  sudo rm -rf flycast

  end_time=$(date +%s)
  duration=$((end_time - start_time))

  echo "Flycast Core updated. The updated core has also been saved as flycast_libretro.7z in /media/usb1/compiled."
  echo "Total time taken: $((duration / 60)) minutes and $((duration % 60)) seconds."
else
  echo "Error: flycast_libretro.so not found. Compilation failed. Check the log at $log_file for details."
fi
