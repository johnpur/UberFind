
=begin

Ubernet Find Non-downloaded Files.

This program will examine a user's Ubernet filelist and compare it against the existing
files on the local system.

options:

  -B (baseline) : creates a database of local directories in the Ubernet system. 
                  
  -C (compare) : compare the indicated user against the baseline data. 
  
  -X (execute) : runs a baseline and compare in order.
                 
The output will be in a table called 'ufcompares' in the 'uberfind' database. Use
the following SQL to sort:

  SELECT * FROM 'uberfind', 'ufcompares' ORDER BY 'artist', 'title'
  
The local data is automatically picked up from the system (it finds the rips, downloads, 
and temporary directories). Prior to a comparison run (either -C or -X) populate the
'filelists' directory with uncompressed filelists from UberNet. It is OK to store groups
of filelists in directories under 'filelists' these will be ignored, this way it is easy
to switch in groups of filelists.

Local files processed:

  Shared Uber Rips
  Shared Uber Downloads
  Unshared downloads (in the '- Downloading -/Uber/MP3' directory)
  Unshared downloads (in the '- Downloading -/Uber/Temp' directory)
  
In addition an exceptions directory ('exceptions') will be processed to weed
out files which are not on the local system, but that we don't want to see on the list again.
These may be unwanted artists/albums, mispellings, or alternate spellings of already
acquired albums. The subdirs will have the exception names and will be empty.

v.1.3.0
04/18/2009

version 1.3 - Accounting for the possibility of nested directories in the filelists.


=end  

require 'find'

# =====================================================================
#
# Establish the connection to the database.
#
# This program uses MySql and assumes the setup is taken care of. The 
# code below is re-using the Junqbox AppPlatform connection data.
#
# A database named "uberfind" must be created prior to running this application.
#
# =====================================================================
require 'active_record'

# ActiveRecord::Base.logger = Logger.new(STDERR)

ActiveRecord::Base.establish_connection(
    :adapter => "mysql", 
    :database => "uberfind",
    :username => "root",
    :password => "junqboxdev",
    :host => "localhost")
  
# Define the data model  
class Ufdetail < ActiveRecord::Base
end

class Ufcompare < ActiveRecord::Base
end
    
# =====================================================================

# Usage check class
class UsageCheck

    def initialize
            
        *@ARGV = *ARGV.map{|a|a.upcase}
    end
    
    def length
        @ARGV.length
    end
    
    def message
        puts "\nUberFind - Ubernet Find Non-downloaded Files"
        puts "\n\noptions: -B : Set the baseline local database (do this first)"
        puts "         -C : Creates the list of non-downloaded files in 'ufcompares' in the 'uberfind' database"
        puts "         -X : Runs a baseline and then a compare in order\n"
    end
    
    def option
        @ARGV[0]
    end    
    
end

# Baseline class
class Baseline
    
    def initialize
        
        ActiveRecord::Schema.verbose = false
        
        ActiveRecord::Schema.define do
            create_table :ufdetails, :force => true do |table|
                table.column :artist, :string
                table.column :year, :string
                table.column :title, :string
            end
            
            add_index :ufdetails, [:artist]
            add_index :ufdetails, [:year]
            add_index :ufdetails, [:title]
        end  
    
    end

    def create
        
        # Fetch the shared directories
        process_flag = 0
        directory_array = Array.new
        $dir_count = 0
        $file_count = 0
        $album_count = 0

        
        File.open("c:\\program files\\uberdcplusplus\\dcplusplus.xml").each {|line|
            if line[1,7] == "<Share>"
                process_flag = 1
            end
            
            if line[1,8] == "</Share>"
                process_flag = 0
            end
            
            if process_flag == 1
                if line[2,11] == "<Directory>"
                    tmp_string = line.gsub("\t\t<Directory>", "")
                    tmp_string2 = tmp_string.gsub("</Directory>", "")
                    tmp_string = tmp_string2.gsub("\\", "/")
                    directory_array.push(tmp_string.chomp!) # remove the record separator
                end
            end
        }
        
        # Add the files in the downloaded and temp directories
        
        directory_array.push("D:/- Downloading -/Uber/MP3")
        directory_array.push("D:/- Downloading -/Uber/Temp")
        
        # Add in the exception directories
        
        directory_array.push("exceptions")
        
        # Process each of the directories
        
        directory_array.each {|shared_directory|
        
            Find::find(shared_directory) {|next_file|
            
                if (File::directory?(next_file))
                    # Next directory found
                    $dir_count = $dir_count + 1
                    process_directory(next_file, shared_directory)
                else
                    # This is not a directory, so ignore
                    $file_count = $file_count + 1
                    Find.prune()
                end
     
            }            
        }
        
    end
    
    def process_directory(next_dir, shared_directory)
        
        # Only process directories with the pattern "artist - title" or "artist - year - title" 

        # First parse the directory tree out
        
        dir_array = Array.new
        dir_array = next_dir.split("/")
        
        # The last array element holds the directory name
        # Break it into artist, year, & title
        
        name_array = Array.new
        name_array = dir_array[dir_array.size-1].split(" - ")
        
        if ((name_array.size == 2) || (name_array.size == 3))
            
            if ((name_array.size == 2) && (name_array[1].length == 4))
                # It's possible that this is a VA album
                if ParseDate::parsedate(name_array[1]) != nil
                    # Set up the standard format with "Various Artists" as the artist tag
                    # Format: "Various Artists" "Year" "Title"
                    name_array[2] = name_array[0]
                    name_array[0] = "Various Artists"
                end
            end
            
            # All records should be 3 elements at this point
                
            # Record the information
            
            if shared_directory != "exceptions"
                $album_count = $album_count + 1
            end
            
            data_record = Ufdetail.new
            data_record.artist = name_array[0]
            data_record.year = name_array[1]
            data_record.title = name_array[2]
            data_record.save
            
            printf("\r Albums found: %d", $album_count)
            
        else
            # The directory was not an album name
        end
        
    end
    
    def report
        
        puts "\n Processing complete."
        puts format("\n Directories: %d Files: %d Albums: %d", $dir_count, $file_count, $album_count)
        
    end

end

# Comparison class
class Compare
    
    # This is where the baseline database is compared against the filelists located in the
    # 'filelists' directory. Each of the saved filelists will be examined in turn and each
    # entry will be compared. If the entry does not exist in the baseline an entry will be made 
    # in the 'ufcompare' database.
    
    def initialize
                
        ActiveRecord::Schema.verbose = false
        
        ActiveRecord::Schema.define do
            create_table :ufcompares, :force => true do |table|
                table.column :owner, :string
                table.column :artist, :string
                table.column :year, :string
                table.column :title, :string
            end
            
            add_index :ufcompares, [:owner]
            add_index :ufcompares, [:artist]
            add_index :ufcompares, [:year]
            add_index :ufcompares, [:title]
        end
        
    end
    
    def create
                        
        $filelist_count = 0
        $album_count = 0
        
        Find::find("filelists") {|next_file|
            
            if (File::directory?(next_file))
                # Should not have any subdirs, so just ignore
                if next_file == "filelists"
                    # Keep processing
                    next
                else
                    # Do't look into subdirs
                    Find.prune()
                end
            else
                # Found a file, so process it
                $filelist_count = $filelist_count + 1
                process_file(next_file)
            end
     
        }
        
    end
    
    def process_file(next_file)
        
        listing_array = Array.new
        
        # Remember who owns this file
        tmp_s1 = next_file
        tmp_s2 = tmp_s1.gsub("filelists/", "")
        uber_name = tmp_s2.gsub(".xml", "")
        
        File.open(next_file).each {|line|
            
            if line[0,17] == "\t<Directory Name="
                tmp_string = line.gsub("\t<Directory Name=", "")
                tmp_string2 = tmp_string.gsub("\">", "")
                tmp_string = tmp_string2.gsub("\"", "")
                listing_array.push(tmp_string.chomp!)
            end
            
            # New directory structures allowed (nesting).
            # Allow for 1-3 tabs before the album listing
            # version 1.3
            
            if line[0,18] == "\t\t<Directory Name="
                tmp_string = line.gsub("\t\t<Directory Name=", "")
                tmp_string2 = tmp_string.gsub("\">", "")
                tmp_string = tmp_string2.gsub("\"", "")
                listing_array.push(tmp_string.chomp!)
            end
            
            if line[0,19] == "\t\t\t<Directory Name="
                tmp_string = line.gsub("\t\t\t<Directory Name=", "")
                tmp_string2 = tmp_string.gsub("\">", "")
                tmp_string = tmp_string2.gsub("\"", "")
                listing_array.push(tmp_string.chomp!)
            end
        }
        
        listing_array.each {|album_info|
        
            name_array = Array.new
            name_array = album_info.split(" - ")
            
            if ((name_array.size == 2) || (name_array.size == 3))
                
                if ((name_array.size == 2) && (name_array[1].length == 4))
                    # It's possible that this is a VA album
                    if ParseDate::parsedate(name_array[1]) != nil
                        # Set up the standard format with "Various Artists" as the artist tag
                        # Format: "Various Artists" "Year" "Title"
                        name_array[2] = name_array[0]
                        name_array[0] = "Various Artists"
                    end
                end
                            
                # All records should be 3 elements at this point
                
                # Record the information
                
                compare_record = Ufdetail.find_by_artist_and_title(name_array[0], name_array[2])
                
                if compare_record
                    # We already have this so skip (do not remember)
                else
              
                    $album_count = $album_count + 1
                    data_record = Ufcompare.new
                    data_record.owner = uber_name
                    data_record.artist = name_array[0]
                    data_record.year = name_array[1]
                    data_record.title = name_array[2]
                    data_record.save
                    
                    printf("\r New Albums found: %d", $album_count)
                end
                 
            else
                # The directory was not an album name
            end
        }
        
        
        
    end
    
    def report
    
        puts "\n Processing complete."
        puts format("\n Filelists: %d New Albums: %d", $filelist_count, $album_count)
            
    end
    
end
  
# =====================================================================================
# Program execution starts here
# =====================================================================================

u = UsageCheck.new

if u.length == 0
    u.message
else
    # Check the passed in command option
    case u.option
      
        when "-B"
            puts "\n Starting creation of a new baseline database...\n\n"
            new_baseline = Baseline.new
            new_baseline.create
            new_baseline.report
        when "-C"
            puts "\n Starting the build of the comparison database...\n\n"
            new_comparison = Compare.new
            new_comparison.create
            new_comparison.report
        when "-X"
            puts "\n Starting creation of a new baseline database...\n\n"
            new_baseline = Baseline.new
            new_baseline.create
            new_baseline.report
            puts "\n Starting the build of the comparison database...\n\n"
            new_comparison = Compare.new
            new_comparison.create
            new_comparison.report
        else
            puts "\nCheck the available options!"
            u.message
    end
end