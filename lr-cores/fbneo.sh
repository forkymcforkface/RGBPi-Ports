#!/bin/bash

clear

confirm_proceed() {
  echo -n "This process can take 10 mins on a Pi5, and 1 hr+ on a Pi4. Do you want to proceed? (y/n) "
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

required_space=1
available_space=$(df --output=avail -BG /media/usb1 | tail -1 | tr -d 'G ')

if [ "$available_space" -lt "$required_space" ]; then
  echo "Error: Not enough free space on /media/usb1. At least 1GB is required."
  exit 1
fi

start_time=$(date +%s)

cd /media/usb1

# Check if FBNeo has already been cloned
if [ ! -d "FBNeo" ]; then
  echo "Cloning FBNeo repository..."
  git clone --recursive https://github.com/libretro/FBNeo > /dev/null 2>&1
fi

cd FBNeo

# Restart the swap if it exists
if [ -f "/media/usb1/swapfile" ]; then
  echo "Reusing existing swap file..."
  sudo swapoff /media/usb1/swapfile 2>/dev/null || true
  sudo swapon /media/usb1/swapfile > /dev/null 2>&1
else
  echo "Creating swap file..."
  sudo dd if=/dev/zero of=/media/usb1/swapfile bs=1G count=1 > /dev/null 2>&1
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

# Generate files and compile FBNeo
echo "Generating files and compiling FBNeo..."
make -j5 -C src/burner/libretro generate-files > /dev/null 2>&1
make -j5 -C src/burner/libretro > /dev/null 2>&1

kill $monitor_pid
wait $monitor_pid 2>/dev/null

echo -ne "\r\033[K"

fbneo_libretro_file=$(find . -name "fbneo_libretro.so")

if [ -n "$fbneo_libretro_file" ]; then
  if [ ! -f /opt/retroarch/cores/fbneo_libretro.so.bak ]; then
    sudo mv /opt/retroarch/cores/fbneo_libretro.so /opt/retroarch/cores/fbneo_libretro.so.bak
  fi

  sudo cp "$fbneo_libretro_file" /opt/retroarch/cores/fbneo_libretro.so

  sync

  # Create the compiled directory if it doesn't exist
  if [ ! -d "/media/usb1/compiled" ]; then
    mkdir /media/usb1/compiled
  fi

  7z a /media/usb1/compiled/fbneo_libretro.7z "$fbneo_libretro_file" > /dev/null 2>&1

  cd /media/usb1
  sudo rm -rf FBNeo

  end_time=$(date +%s)
  duration=$((end_time - start_time))


  echo "FBNeo core updated. The updated core has also been saved as fbneo_libretro.7z in /media/usb1/compiled."
  echo "Total time taken: $((duration / 60)) minutes and $((duration % 60)) seconds."
else
  echo "Error: fbneo_libretro.so not found. Compilation failed. Try running this script again."
fi
