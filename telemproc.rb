require "time"

# Always wait for input at exit so that command window doesn't close.
at_exit do
  puts "Finished, press Enter to close."
  $stdin.gets
end

# Configuration
# Maximum voltage drop (in volts) due to internal resistance. If the cell 
# voltage increases above this value, we will assume that a new battery has been
# used.
max_voltage_diff = 1

# Maximum altitude difference between measurements (in metres). Any change in 
# altitude greater than this value will be ignored.
max_altitude_diff = 2

# Minimum current (in amps). The copter will be considered grounded if the
# current is below this value.
min_current = 2

# Some data needs to be checked less frequently so that we can spot genuine 
# changes rather than fluctuations. This is how frequently (in data points) we 
# check. If data is logged ten times per second, a value of 5 would equal a half
# second frequency.
smooth_units = 10

# The expected headers, on order, from the CSV.
expected_headers = ["Date", 
                    "Time",
                    "SWR",
                    "RSSI",
                    "A1",
                    "A2",
                    "GPS Date",
                    "GPS Time",
                    "Long",
                    "Lat",
                    "Course",
                    "GPS Speed",
                    "GPS Alt",
                    "Baro Alt",
                    "Vertical Speed",
                    "Temp1",
                    "Temp2",
                    "RPM",
                    "Fuel",
                    "Cell volts",
                    "Cell 1",
                    "Cell 2",
                    "Cell 3",
                    "Cell 4",
                    "Cell 5",
                    "Cell 6",
                    "Current",
                    "Consumption",
                    "Vfas",
                    "AccelX",
                    "AccelY",
                    "AccelZ",
                    "Rud",
                    "Ele",
                    "Thr",
                    "Ail",
                    "S1",
                    "S2",
                    "LS",
                    "RS",
                    "SA",
                    "SB",
                    "SC",
                    "SD",
                    "SE",
                    "SF",
                    "SG",
                    "SH"]

# The information in which we're interested. Each value must match the 
# associated header exactly.
wanted_data = ["Date",
              "Time",
              "Baro Alt",
              "Cell volts",
              "Cell 1",
              "Cell 2",
              "Cell 3",
              "Current",
              "Consumption",
              "Rud",
              "Ele",
              "Thr",
              "Ail"]

# Usage text
# @@@ TODO
usage = ""

# Check that we have been given some arguments
if (ARGV.length <1)
  puts "You must specify at least one file to process."
  puts usage
end

# Loop over the arguments
ARGV.each do |file_name|
  
  file_base_name = file_name.split(".")[0..-2].join
  
  # Attempt to open the input file
  begin
    input_file = File.open(file_name, "r")
  rescue
    # Failed to open the file. Print an error and move on.
    puts "Cannot open " + file_name + " for reading."
    next    
  end
  
  # Attempt to open the output file
  begin
    output_file = File.open(file_base_name + "_processed.csv", "w")
  rescue
    # Failed to open the file. Print an error and move on.
    puts "Cannot open " + file_base_name + "_processed.csv for writing."
    next    
  end
  
  # Read the CSV headers
  headers = input_file.readline.chomp
  
  # Check that the headers are what we're expecting
  if headers != expected_headers.join(",")
    puts "The headers of " + file_name + " do not match what we were expecting."
    next
  end
  
  # Write the headers to the new file.
  output_file.puts wanted_data.join(",")
  
  # Keep track of old data. For now, initialize a hash of zeroes.
  old_data = Hash[expected_headers.zip Array.new(headers.length, 0)]
  ref_data = Hash[expected_headers.zip Array.new(headers.length, 0)]
  
  # Keep track of flight times, altitude, and batteries used.
  battery_lives = []
  altitudes = []
  flight_start = ""
  voltage_end = 0
  altitude_offset = 0
    
  # Loop over the file
  input_file.each_line.with_index do |line, index|
    
    # We don't want the header row, so only parse data after that.
    if index > 0

      # Put the current line into a hash.
      current_data = Hash[expected_headers.zip line.split(",")]

      # We'll write out the data we want to a new file.
      output_data = Array[]

      # Do special processing here.
      # Convert the time into something Excel can understand.
      current_data["Time"] = current_data["Time"][0..-5]

      # Basic barometer calibration
      if index == 1
        altitude_offset = current_data["Baro Alt"].to_f
      end

      # Remove anomalies in the barometer data.
      if (current_data["Baro Alt"].to_f - old_data["Baro Alt"].to_f).abs >
          max_altitude_diff
        # Altitude data is rubbish. Use the old data.
        current_data["Baro Alt"] = old_data["Baro Alt"]
      else
        # Altitude data is OK. Apply the offset.
        # @@@ TODO
      end

      if altitudes.length > 0
        if current_data["Baro Alt"].to_f > altitudes[-1]
          altitudes[-1] = current_data["Baro Alt"].to_f
        end
      end

      # Check for takeoff/landing/batteries less frequently.
      if ((index - 1) % smooth_units) == 0

        # Look at the current draw to work out whether the copter is in the air.
        # Taking off
        if current_data["Current"].to_f >= min_current && 
           ref_data["Current"].to_f < min_current
        
          # The copter has just taken off. Log the flight start time.
          flight_start = Time.parse(current_data["Date"] + " " +
                                    current_data["Time"])
          
          # See if this is a new battery
          if current_data["Cell volts"].to_f - voltage_end > max_voltage_diff
            # Create a new flight time log
            battery_lives[battery_lives.length] = 0
          end
          
          # Start a new log for the altitude.
          altitudes[altitudes.length] = 0
          
          # Reset the altitude offset
          altitude_offset = current_data["Baro Alt"].to_f
          
        end
        
        # Landing
        if current_data["Current"].to_f <= min_current && 
           ref_data["Current"].to_f > min_current
        
          # The copter has just landed. Log the length of the flight.
          flight_end = Time.parse(current_data["Date"] + " " +
                                  current_data["Time"])       
          battery_lives[-1] = battery_lives[-1].to_f + 
                                   (flight_end - flight_start).to_f
          
          # Log the voltage.
          voltage_end = current_data["Cell volts"].to_f  
          
          # Reset the altitude offset
          altitude_offset = current_data["Baro Alt"].to_f
          
        end  
      
        ref_data = current_data
      end
      
      # Loop over the data we want, extracting it from the current row.
      wanted_data.each do |field|

        # Find the value of the current field in the current row.
        current_value = current_data[field]
   
        # Add the current value to the array of data to be written to file.
        output_data << current_value
      end
      
      output_file.puts output_data.join(",")
      
      # Finally, we replace the old data with the new data.
      old_data = current_data
      
    end
  end
  
  # Report the altitude details:
  puts file_name + " contains data for " + altitudes.length.to_s + " flights:" 
  
  altitudes.each.with_index do |alt, flight|
    puts "Flight " + (flight + 1).to_s + ": " + alt.to_s + "m"
  end
  
  # Report the battery lives:
  puts file_name + " contains data for " + battery_lives.length.to_s + 
       " LiPos worth of flights:" 

  battery_lives.each.with_index do |life, lipo|
    puts "LiPo " + (lipo + 1).to_s + ": " + Time.at(life).strftime('%M:%S')
  end
  
  # Close the files
  input_file.close
  output_file.close
  
end