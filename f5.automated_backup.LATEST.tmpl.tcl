#TMSH-VERSION: 13.1.0.1

# iApp VERSIONS (From what I gathered perusing DevCentral)
# ~v2.0  - 20140312 - Initially posted releases (v11.4.0-11.6.x? compatibility). (Developed/posted by Thomas Schockaert)
# v2.1.1 - 20160916 - Retooled SMB upload from smbclient to "mount -t cifs" (v12.1+ compatibility). (Developed/posted by MAG)
# v2.2.1 - 20171214 - Allowed multiple instances of iApp by leveraging $tmsh::app_name to create unique object names. (Developed by Daniel Tavernier/tabernarious)
# v2.2.2 - 20171214 - Added "/" to "mount -t cifs" command and clarified/expanded help for SMB (CIFS) Destination Parameters. (Developed by Daniel Tavernier/tabernarious)
# v2.2.3 - 20171214 - Set many fields to "required" and set reasonable default values to prevent loading/configuration errors. Expanded help regarding private keys. (Developed by Daniel Tavernier/tabernarious)
# v2.2.4 - 20171214 - Added fix to force FTP to use binary upload. (Copied code posted by Roy van Dongen, posted by Daniel Tavernier/tabernarious)
# v2.2.4a - 20171215 - Added items to FUTURE list.
# v2.2.5 - 20171228 - Added notes about special characters in passwords. Added Deployment Information and ConfigSync sections. (Developed by Daniel Tavernier/tabernarious)
# v2.2.5a - 20180117 - Added items to FUTURE list.
# v2.2.5b4 - 20180118 - Moved encrypted values for SMB/CIFS to shell script which eliminates ConfigSync issues. Fixed long-password issue by using "-A" with openssl so that base64 encoded strings are written and read as a single line. (Developed by Daniel Tavernier/tabernarious)
# v2.2.5b4+ - 20180118 - Refining changes to SMB/CIFS and replicating to other remote copy types. (Developed by Daniel Tavernier/tabernarious)
# v3.0.0 - 20180124 - (Developed by Daniel Tavernier/tabernarious)
#                   - Eliminated ConfigSync issues and removed ConfigSync notes section. (Encrypted values now in $script instead of local file.)
#                   - Passwords now have no length limits. (Using "-A" with openssl which reads/writes base64 encoded strings as a single line.)
#                   - Added $script error checking for all remote backup types. (Using 'catch' to prevent tcl errors when $script aborts.)
#                   - Backup files are cleaned up after $script error due to new error checking.
#                   - Added logging. (Run logs sent to '/var/log/ltm' via logger command which is compatible with BIG-IP Remote Logging configuration (syslog). Run logs AND errors sent to '/var/tmp/scriptd.out'. Errors may include plain-text passwords which should not be in /var/log/ltm or syslog.)
#                   - Added custom cipher option for SCP.
#                   - Added StrictHostKeyChecking=no option.
#                   - Combined SCP and SFTP because they are both using SCP to perform the remote copy.

# FUTURE
# - Fix tcl warnings if possible.
# - Escape special characters in password for SMB/CIFS (maybe others).

#REFERENCES
# F5 Automated Backups - The Right Way (https://devcentral.f5.com/articles/f5-automated-backups-the-right-way)
# PASTEBIN f5.automated_backup_v2.0 (https://pastebin.com/YbDj3eMN)
# Complete F5 Automated Backup Solution (https://devcentral.f5.com/codeshare/complete-f5-automated-backup-solution?lc=1)
# Complete F5 Automated Backup Solution #2 (https://devcentral.f5.com/codeshare/complete-f5-automated-backup-solution-2-957)
# Automated Backup Solution (https://devcentral.f5.com/questions/automated-backup-solution)
# Generate Config Backup (https://devcentral.f5.com/codeshare?sid=285)
# PASTEBIN f5.automated_backup_v2.2.5 (https://pastebin.com/TENAivwW)

cli admin-partitions {
    update-partition Common
}
sys application template /Common/f5.automated_backup.v3.0.0 {
    actions {
        definition {
            html-help {
            }
            implementation {
                package require iapp 1.0.0
	        	iapp::template start

	        	tmsh::cd ..

				## Backup type handler
				set backup_type $::backup_type__backup_type_select
				set create_backup_command_append_pass ""
				set create_backup_command_append_keys ""
				if { $backup_type eq "UCS (User Configuration Set)" } {
					set create_backup_command "tmsh::save /sys ucs"
					set backup_directory /var/local/ucs
					# Backup passphrase usage
					if { $::backup_type__backup_passphrase_select eq "Yes" } {
						set backup_passphrase $::backup_type__backup_passphrase
						set create_backup_command_append_pass "passphrase $backup_passphrase"
					}
					# Backup private key inclusion
					if { $::backup_type__backup_includeprivatekeys eq "No" } {
						set create_backup_command_append_keys "no-private-key"
					}
					set backup_file_name ""
					set backup_file_name_extension ""
					set backup_file_script_extension ".ucs"
					set scfextensionfix ""
				}
				elseif { $backup_type eq "SCF (Single Configuration File)" } {
					set create_backup_command "tmsh::save /sys config file"
					set backup_directory /var/local/scf
					set backup_file_name_extension ".scf"
					set backup_file_script_extension ""
				}

		        if { $::destination_parameters__protocol_enable eq "Remotely via SCP/SFTP" } {
					# Get the F5 Master key
					set f5masterkey [exec f5mku -K]
					# Store the target server information securely, encrypted with the unit key
					set encryptedusername [exec echo "$::destination_parameters__scp_remote_username" | openssl aes-256-ecb -salt -a -A -k ${f5masterkey}]
					set encryptedserver [exec echo "$::destination_parameters__scp_remote_server" | openssl aes-256-ecb -salt -a -A -k ${f5masterkey}]
					set encrypteddirectory [exec echo "$::destination_parameters__scp_remote_directory" | openssl aes-256-ecb -salt -a -A -k ${f5masterkey}]
					# Clean the private key data before cleanup
					set cleaned_privatekey [exec echo "$::destination_parameters__scp_sshprivatekey" | sed -e "s/BEGIN RSA PRIVATE KEY/BEGIN;RSA;PRIVATE;KEY/g" -e "s/END RSA PRIVATE KEY/END;RSA;PRIVATE;KEY/g" -e "s/ /\\\n/g" -e "s/;/ /g"]
					# Encrypt the private key data before dumping to a file
					set encrypted_privatekey [exec echo "$cleaned_privatekey" | openssl aes-256-ecb -salt -a -A -k ${f5masterkey}]
                    # Set optional cipher for SCP (e.g. aes256-gcm@openssh.com)
                    if { "$::destination_parameters__scp_cipher" equals "" } {
                        set scp_cipher ""
                    } else {
                        set scp_cipher "-c $::destination_parameters__scp_cipher"
                    }
                    # Set optional "StrictHostKeyChecking=no"
                    if { "$::destination_parameters__scp_stricthostkeychecking" equals "Yes" } {
                        set scp_stricthostkeychecking "-o StrictHostKeyChecking=yes"
                    } else {
                        set scp_stricthostkeychecking "-o StrictHostKeyChecking=no"
                    }
					# Create the iCall action
					set script {
                        exec echo "f5.automated_backup iApp TMSHAPPNAME: STARTED" >> /var/tmp/scriptd.out
                        exec logger -p local0.info "f5.automated_backup iApp TMSHAPPNAME: STARTED"
						# Get the hostname of the device we're running on
						set host [tmsh::get_field_value [lindex [tmsh::get_config sys global-settings] 0] hostname]
						# Get the current date and time in a specific format
						set cdate [clock format [clock seconds] -format "FORMAT"]
						# Form the filename for the backup
						set fname "${cdate}BACKUPFILENAMEXTENSION"
						# Run the 'create backup' command
                        exec echo "f5.automated_backup iApp TMSHAPPNAME: $fname GENERATING" >> /var/tmp/scriptd.out
                        exec logger -p local0.info "f5.automated_backup iApp TMSHAPPNAME: $fname GENERATING"
						BACKUPCOMMAND $fname BACKUPAPPEND_PASS BACKUPAPPEND_KEYS
                        exec echo "f5.automated_backup iApp TMSHAPPNAME: $fname SAVED LOCALLY" >> /var/tmp/scriptd.out
                        exec logger -p local0.info "f5.automated_backup iApp TMSHAPPNAME: $fname SAVED LOCALLY"
						# Set the script filename
						set scriptfile "/var/tmp/f5.automated_backup__TMSHAPPNAME_scp.sh"
						# Clean, recreate, and run a custom bash script that will perform the SCP upload
						exec rm -f $scriptfile
						exec echo "yes"
						exec echo -e "scp_function()\n{\n\tf5masterkey=\$(f5mku -K)\n\tusername=\$(echo \"ENCRYPTEDUSERNAME\" | openssl aes-256-ecb -salt -a -A -d -k \${f5masterkey})\n\tserver=\$(echo \"ENCRYPTEDSERVER\" | openssl aes-256-ecb -salt -a -A -d -k \${f5masterkey})\n\tdirectory=\$(echo \"ENCRYPTEDDIRECTORY\" | openssl aes-256-ecb -salt -a -A -d -k \${f5masterkey})\n\techo \"ENCRYPTEDPRIVATEKEY\" | openssl aes-256-ecb -salt -a -A -d -k \${f5masterkey} > /var/tmp/TMSHAPPNAME_scp.key\n\n\tchmod 600 /var/tmp/TMSHAPPNAME_scp.key\n\tscp -i /var/tmp/TMSHAPPNAME_scp.key SCPCIPHER SCPSTRICTHOSTKEYCHECKING BACKUPDIRECTORY/${fname}BACKUPFILESCRIPTEXTENSION \${username}@\${server}:\${directory} 2>> /var/tmp/scriptd.out\n\tscp_result=\$?\n\trm -f /var/tmp/TMSHAPPNAME_scp.key\n\treturn \$scp_result\n}\n\nscp_function" > $scriptfile
						exec chmod +x $scriptfile
                        exec echo "f5.automated_backup iApp TMSHAPPNAME: $fname REMOTE COPY (SCP) STARTING" >> /var/tmp/scriptd.out
                        exec logger -p local0.info "f5.automated_backup iApp TMSHAPPNAME: $fname REMOTE COPY (SCP) STARTING"
						if { [catch {exec $scriptfile}] } {
                            exec echo "f5.automated_backup iApp TMSHAPPNAME: $fname REMOTE COPY (SCP) FAILED (check for errors above)" >> /var/tmp/scriptd.out
                            exec logger -p local0.crit "f5.automated_backup iApp TMSHAPPNAME: $fname REMOTE COPY (SCP) FAILED (see /var/tmp/scriptd.out for errors)"
                        } else {
                            exec echo "f5.automated_backup iApp TMSHAPPNAME: $fname REMOTE COPY (SCP) SUCCEEDED" >> /var/tmp/scriptd.out
                            exec logger -p local0.notice "f5.automated_backup iApp TMSHAPPNAME: $fname REMOTE COPY (SCP) SUCCEEDED"
                        }
						# Clean up local files
						exec rm -f $scriptfile
                        exec rm -f /var/tmp/TMSHAPPNAME_scp.key
						exec rm -f BACKUPDIRECTORY/$fnameBACKUPFILESCRIPTEXTENSION
                        exec echo "f5.automated_backup iApp TMSHAPPNAME: FINISHED" >> /var/tmp/scriptd.out
                        exec logger -p local0.info "f5.automated_backup iApp TMSHAPPNAME: FINISHED"
					}
					set script [string map [list FORMAT [lindex [split $::destination_parameters__filename_format " "] 0]] $script]
					set script [string map [list BACKUPFILENAMEXTENSION $backup_file_name_extension BACKUPFILESCRIPTEXTENSION $backup_file_script_extension BACKUPDIRECTORY $backup_directory BACKUPCOMMAND $create_backup_command BACKUPAPPEND_PASS $create_backup_command_append_pass BACKUPAPPEND_KEYS $create_backup_command_append_keys TMSHAPPNAME $tmsh::app_name ENCRYPTEDUSERNAME $encryptedusername ENCRYPTEDSERVER $encryptedserver ENCRYPTEDDIRECTORY $encrypteddirectory ENCRYPTEDPRIVATEKEY $encrypted_privatekey SCPCIPHER $scp_cipher SCPSTRICTHOSTKEYCHECKING $scp_stricthostkeychecking] $script]
		        }
		        elseif { $::destination_parameters__protocol_enable eq "Remotely via SFTP--DEPRECATED)" } {
                    # SFTP was originally implemented EXACTLY THE SAME as SCP. While refining the SCP implementation and adding detailed notes and documentation it no longer made sense to maintain these in parallel.
                    # Set the config file
					set configfile "/config/f5.automated_backup__${tmsh::app_name}_sftp.conf"
					# Clean the configuration file for this protocol_enable
					exec rm -f $configfile
					# Get the F5 Master key
					set f5masterkey [exec f5mku -K]
					# Store the target server information securely, encrypted with the unit key
					exec echo "$::destination_parameters__sftp_remote_username" | openssl aes-256-ecb -salt -a -k ${f5masterkey} > $configfile
					exec echo "$::destination_parameters__sftp_remote_server" | openssl aes-256-ecb -salt -a -k ${f5masterkey} >> $configfile
					exec echo "$::destination_parameters__sftp_remote_directory" | openssl aes-256-ecb -salt -a -k ${f5masterkey} >> $configfile
					# Clean the private key data before cleanup
					set cleaned_privatekey [exec echo "$::destination_parameters__sftp_sshprivatekey" | sed -e "s/BEGIN RSA PRIVATE KEY/BEGIN;RSA;PRIVATE;KEY/g" -e "s/END RSA PRIVATE KEY/END;RSA;PRIVATE;KEY/g" -e "s/ /\\\n/g" -e "s/;/ /g"]
					# Encrypt the private key data before dumping to a file
					set encrypted_privatekey [exec echo "$cleaned_privatekey" | openssl aes-256-ecb -salt -a -k ${f5masterkey}]
					# Store the target server information securely, encrypted with the unit key
					exec echo "$encrypted_privatekey" >> $configfile
					# Create the iCall action
					set script {
                        exec echo "f5.automated_backup iApp TMSHAPPNAME: STARTED" >> /var/tmp/scriptd.out
                        exec logger -p local0.info "f5.automated_backup iApp TMSHAPPNAME: STARTED"
						# Get the hostname of the device we're running on
						set host [tmsh::get_field_value [lindex [tmsh::get_config sys global-settings] 0] hostname]
						# Get the current date and time in a specific format
						set cdate [clock format [clock seconds] -format "FORMAT"]
						# Form the filename for the backup
						set fname "${cdate}BACKUPFILENAMEXTENSION"
						# Run the 'create backup' command
                        exec echo "f5.automated_backup iApp TMSHAPPNAME: $fname GENERATING" >> /var/tmp/scriptd.out
                        exec logger -p local0.info "f5.automated_backup iApp TMSHAPPNAME: $fname GENERATING"
						BACKUPCOMMAND $fname BACKUPAPPEND_PASS BACKUPAPPEND_KEYS
                        exec echo "f5.automated_backup iApp TMSHAPPNAME: $fname SAVED LOCALLY" >> /var/tmp/scriptd.out
                        exec logger -p local0.info "f5.automated_backup iApp TMSHAPPNAME: $fname SAVED LOCALLY"
						# Set the config file
						set configfile "/config/f5.automated_backup__TMSHAPPNAME_sftp.conf"
						# Set the script filename
						set scriptfile "/var/tmp/f5.automated_backup__TMSHAPPNAME_sftp.sh"
						# Clean, recreate, run and reclean a custom bash script that will perform the SCP upload
						exec rm -f $scriptfile
						exec echo "yes"
						exec echo -e "put()\n{\n\tfields=\"username server directory\"\n\ti=1\n\tf5masterkey=\$(f5mku -K)\n\tfor current_field in \$fields ; do\n\t\tsedcommand=\"\${i}p\"\n\t\tcurrent_encrypted_value=\$(sed -n \"\$sedcommand\" $configfile)\n\t\tcurrent_decrypted_value=\$(echo \"\$current_encrypted_value\" | openssl aes-256-ecb -salt -a -d -k \$f5masterkey)\n\t\teval \"\$current_field=\$current_decrypted_value\"\n\t\tlet i=\$i+1\n\t\tunset current_encrypted_value current_decrypted_value sedcommand\n\tdone\n\tsed -n '4,\$p' $configfile | openssl aes-256-ecb -salt -a -d -k \$f5masterkey > /var/tmp/scp.key\n\tchmod 600 /var/tmp/scp.key\n\tscp -i /var/tmp/scp.key BACKUPDIRECTORY/$fnameBACKUPFILESCRIPTEXTENSION \${username}@\${server}:\${directory}\n\trm -f /var/tmp/scp.key\n\treturn \$?\n}\n\nput" > $scriptfile
						exec chmod +x $scriptfile
                        exec echo "f5.automated_backup iApp TMSHAPPNAME: $fname REMOTE COPY (SFTP) STARTING" >> /var/tmp/scriptd.out
                        exec logger -p local0.info "f5.automated_backup iApp TMSHAPPNAME: $fname REMOTE COPY (SFTP) STARTING"
						exec $scriptfile
						exec rm -f $scriptfile
						# Remove the backup file from the F5
						exec rm -f BACKUPDIRECTORY/$fnameBACKUPFILESCRIPTEXTENSION
                        exec echo "f5.automated_backup iApp TMSHAPPNAME: FINISHED" >> /var/tmp/scriptd.out
                        exec logger -p local0.info "f5.automated_backup iApp TMSHAPPNAME: FINISHED"
					}
					set script [string map [list FORMAT [lindex [split $::destination_parameters__filename_format " "] 0]] $script]
					set script [string map [list BACKUPFILENAMEXTENSION $backup_file_name_extension BACKUPFILESCRIPTEXTENSION $backup_file_script_extension BACKUPDIRECTORY $backup_directory BACKUPCOMMAND $create_backup_command BACKUPAPPEND_PASS $create_backup_command_append_pass BACKUPAPPEND_KEYS $create_backup_command_append_keys TMSHAPPNAME $tmsh::app_name] $script]
		        }
				elseif { $::destination_parameters__protocol_enable eq "Remotely via FTP" } {
					# Get the F5 Master key
					set f5masterkey [exec f5mku -K]
					# Store the target server information securely, encrypted with the unit key
					set encryptedusername [exec echo "$::destination_parameters__ftp_remote_username" | openssl aes-256-ecb -salt -a -A -k ${f5masterkey}]
					set encryptedpassword [exec echo "$::destination_parameters__ftp_remote_password" | openssl aes-256-ecb -salt -a -A -k ${f5masterkey}]
					set encryptedserver [exec echo "$::destination_parameters__ftp_remote_server" | openssl aes-256-ecb -salt -a -A -k ${f5masterkey}]
					set encrypteddirectory [exec echo "$::destination_parameters__ftp_remote_directory" | openssl aes-256-ecb -salt -a -A -k ${f5masterkey}]
					# Create the iCall action
					set script {
                        exec echo "f5.automated_backup iApp TMSHAPPNAME: STARTED" >> /var/tmp/scriptd.out
                        exec logger -p local0.info "f5.automated_backup iApp TMSHAPPNAME: STARTED"
						# Get the hostname of the device we're running on
						set host [tmsh::get_field_value [lindex [tmsh::get_config sys global-settings] 0] hostname]
						# Get the current date and time in a specific format
						set cdate [clock format [clock seconds] -format "FORMAT"]
						# Form the filename for the backup
						set fname "${cdate}BACKUPFILENAMEXTENSION"
						# Run the 'create backup' command
                        exec echo "f5.automated_backup iApp TMSHAPPNAME: $fname GENERATING" >> /var/tmp/scriptd.out
                        exec logger -p local0.info "f5.automated_backup iApp TMSHAPPNAME: $fname GENERATING"
						BACKUPCOMMAND $fname BACKUPAPPEND_PASS BACKUPAPPEND_KEYS
                        exec echo "f5.automated_backup iApp TMSHAPPNAME: $fname SAVED LOCALLY" >> /var/tmp/scriptd.out
                        exec logger -p local0.info "f5.automated_backup iApp TMSHAPPNAME: $fname SAVED LOCALLY"
						# Set the config file
						set configfile "/config/f5.automated_backup__TMSHAPPNAME_ftp.conf"
						# Set the script filename
						set scriptfile "/var/tmp/f5.automated_backup__TMSHAPPNAME_ftp.sh"
						# Clean, recreate, run and reclean a custom bash script that will perform the FTP upload
						exec rm -f $scriptfile
                        # Updated command v2.2.4 to force binary transfer.
                        exec echo -e "ftp_function()\n{\n\tf5masterkey=\$(f5mku -K)\n\tusername=\$(echo \"ENCRYPTEDUSERNAME\" | openssl aes-256-ecb -salt -a -A -d -k \${f5masterkey})\n\tpassword=\$(echo \"ENCRYPTEDPASSWORD\" | openssl aes-256-ecb -salt -a -A -d -k \${f5masterkey})\n\tserver=\$(echo \"ENCRYPTEDSERVER\" | openssl aes-256-ecb -salt -a -A -d -k \${f5masterkey})\n\tdirectory=\$(echo \"ENCRYPTEDDIRECTORY\" | openssl aes-256-ecb -salt -a -A -d -k \${f5masterkey})\n\n\tftp_return=\$(ftp -n \${server} << END_FTP\nquote USER \${username}\nquote PASS \${password}\nbinary\nput BACKUPDIRECTORY/${fname}BACKUPFILESCRIPTEXTENSION \${directory}/${fname}BACKUPFILESCRIPTEXTENSION\nquit\nEND_FTP\n)\n\tif \[ \"\$ftp_return\" == \"\" \]\n\tthen\n\t\treturn 0\n\telse\n\t\techo \"\$ftp_return\" >> /var/tmp/scriptd.out\n\t\treturn 1\n\tfi\n}\n\nftp_function" > $scriptfile
						# Original command which allowed ascii transfer.
                        #exec echo -e "put()\n{\n\tfields=\"username password server directory\"\n\ti=1\n\tf5masterkey=\$(f5mku -K)\n\tfor current_field in \$fields ; do\n\t\tsedcommand=\"\${i}p\"\n\t\tcurrent_encrypted_value=\$(sed -n \"\$sedcommand\" $configfile)\n\t\tcurrent_decrypted_value=\$(echo \"\$current_encrypted_value\" | openssl aes-256-ecb -salt -a -d -k \$f5masterkey)\n\t\teval \"\$current_field=\$current_decrypted_value\"\n\t\tlet i=\$i+1\n\t\tunset current_encrypted_value current_decrypted_value sedcommand\n\tdone\n\tftp -n \${server} << END_FTP\nquote USER \${username}\nquote PASS \${password}\nput BACKUPDIRECTORY/${fname}BACKUPFILESCRIPTEXTENSION \${directory}/${fname}BACKUPFILESCRIPTEXTENSION\nquit\nEND_FTP\n\treturn \$?\n}\n\nput" > $scriptfile
						exec chmod +x $scriptfile
                        exec echo "f5.automated_backup iApp TMSHAPPNAME: $fname REMOTE COPY (FTP) STARTING" >> /var/tmp/scriptd.out
                        exec logger -p local0.info "f5.automated_backup iApp TMSHAPPNAME: $fname REMOTE COPY (FTP) STARTING"
						if { [catch {exec $scriptfile}] } {
                            exec echo "f5.automated_backup iApp TMSHAPPNAME: $fname REMOTE COPY (FTP) FAILED (check for errors above)" >> /var/tmp/scriptd.out
                            exec logger -p local0.crit "f5.automated_backup iApp TMSHAPPNAME: $fname REMOTE COPY (FTP) FAILED (see /var/tmp/scriptd.out for errors)"
                        } else {
                            exec echo "f5.automated_backup iApp TMSHAPPNAME: $fname REMOTE COPY (FTP) SUCCEEDED" >> /var/tmp/scriptd.out
                            exec logger -p local0.notice "f5.automated_backup iApp TMSHAPPNAME: $fname REMOTE COPY (FTP) SUCCEEDED"
                        }
						# Clean up local files
						exec rm -f $scriptfile
						exec rm -f BACKUPDIRECTORY/$fnameBACKUPFILESCRIPTEXTENSION
                        exec echo "f5.automated_backup iApp TMSHAPPNAME: FINISHED" >> /var/tmp/scriptd.out
                        exec logger -p local0.info "f5.automated_backup iApp TMSHAPPNAME: FINISHED"
					}
					set script [string map [list FORMAT [lindex [split $::destination_parameters__filename_format " "] 0]] $script]
					set script [string map [list BACKUPFILENAMEXTENSION $backup_file_name_extension BACKUPFILESCRIPTEXTENSION $backup_file_script_extension BACKUPDIRECTORY $backup_directory BACKUPCOMMAND $create_backup_command BACKUPAPPEND_PASS $create_backup_command_append_pass BACKUPAPPEND_KEYS $create_backup_command_append_keys TMSHAPPNAME $tmsh::app_name ENCRYPTEDUSERNAME $encryptedusername ENCRYPTEDPASSWORD $encryptedpassword ENCRYPTEDSERVER $encryptedserver ENCRYPTEDDIRECTORY $encrypteddirectory] $script]
				}
				elseif { $::destination_parameters__protocol_enable eq "Remotely via SMB/CIFS" } {
					# Get the F5 Master key
					set f5masterkey [exec f5mku -K]
					# Store the target server information securely, encrypted with the unit key
					set encryptedusername [exec echo "$::destination_parameters__smb_remote_username" | openssl aes-256-ecb -salt -a -A -k ${f5masterkey}]
					set encryptedpassword [exec echo "$::destination_parameters__smb_remote_password" | openssl aes-256-ecb -salt -a -A -k ${f5masterkey}]
					set encryptedmsdomain [exec echo "$::destination_parameters__smb_remote_domain" | openssl aes-256-ecb -salt -a -A -k ${f5masterkey}]
					set encryptedserver [exec echo "$::destination_parameters__smb_remote_server" | openssl aes-256-ecb -salt -a -A -k ${f5masterkey}]
					set encryptedmsshare [exec echo "$::destination_parameters__smb_remote_path" | openssl aes-256-ecb -salt -a -A -k ${f5masterkey}]
					set encryptedmssubdir [exec echo "$::destination_parameters__smb_remote_directory" | openssl aes-256-ecb -salt -a -A -k ${f5masterkey}]
					set encryptedmountp [exec echo "$::destination_parameters__smb_local_mountdir" | openssl aes-256-ecb -salt -a -A -k ${f5masterkey}]
					# Create the iCall action
					set script {
                        exec echo "f5.automated_backup iApp TMSHAPPNAME: STARTED" >> /var/tmp/scriptd.out
                        exec logger -p local0.info "f5.automated_backup iApp TMSHAPPNAME: STARTED"
						# Get the hostname of the device we're running on
						set host [tmsh::get_field_value [lindex [tmsh::get_config sys global-settings] 0] hostname]
						# Get the current date and time in a specific format
						set cdate [clock format [clock seconds] -format "FORMAT"]
						# Form the filename for the backup
						set fname "${cdate}BACKUPFILENAMEXTENSION"
						# Run the 'create backup' command
                        exec echo "f5.automated_backup iApp TMSHAPPNAME: $fname GENERATING" >> /var/tmp/scriptd.out
                        exec logger -p local0.info "f5.automated_backup iApp TMSHAPPNAME: $fname GENERATING"
						BACKUPCOMMAND $fname BACKUPAPPEND_PASS BACKUPAPPEND_KEYS
                        exec echo "f5.automated_backup iApp TMSHAPPNAME: $fname SAVED LOCALLY" >> /var/tmp/scriptd.out
                        exec logger -p local0.info "f5.automated_backup iApp TMSHAPPNAME: $fname SAVED LOCALLY"
						# Set the script filename
						set scriptfile "/var/tmp/f5.automated_backup__TMSHAPPNAME_smb.sh"
						# Clean, recreate, run and reclean a custom bash script that will perform the SMB upload
						exec rm -f $scriptfile
                        exec echo -e "\#\!/bin/sh\nf5masterkey=\$(f5mku -K)\nusername=\$(echo \"ENCRYPTEDUSERNAME\" | openssl aes-256-ecb -salt -a -A -d -k \${f5masterkey})\npassword=\$(echo \"ENCRYPTEDPASSWORD\" | openssl aes-256-ecb -salt -a -A -d -k \${f5masterkey})\nmsdomain=\$(echo \"ENCRYPTEDMSDOMAIN\" | openssl aes-256-ecb -salt -a -A -d -k \${f5masterkey})\nserver=\$(echo \"ENCRYPTEDSERVER\" | openssl aes-256-ecb -salt -a -A -d -k \${f5masterkey})\nmsshare=\$(echo \"ENCRYPTEDMSSHARE\" | openssl aes-256-ecb -salt -a -A -d -k \${f5masterkey})\nmssubdir=\$(echo \"ENCRYPTEDMSSUBDIR\" | openssl aes-256-ecb -salt -a -A -d -k \${f5masterkey})\nmountp=\$(echo \"ENCRYPTEDMOUNTP\" | openssl aes-256-ecb -salt -a -A -d -k \${f5masterkey})\ncd /var/local/ucs\nif \[ \! -d \${mountp} \]\nthen\n\tmkdir -p \${mountp}\n\tif \[ \$? -ne 0 \]\n\tthen\n\t\trm -f $fnameBACKUPFILESCRIPTEXTENSION\n\t\texit 1\n\tfi\nfi\nmount -t cifs //\${server}/\${msshare} \${mountp} -o user=\${username}%\${password},domain=\${msdomain} 2>> /var/tmp/scriptd.out\nif \[ \$? -ne 0 \]\n\tthen\n\trm -f $fnameBACKUPFILESCRIPTEXTENSION\n\texit 1\nfi\nfONSMB=\$(ls -t \${mountp}\${mssubdir}/\*.ucs 2>/dev/null| head -n 1 2>/dev/null)\nif \[ \"X\"\${fONSMB} \!= \"X\" \]\n\tthen\n\tsum1=\$(md5sum $fnameBACKUPFILESCRIPTEXTENSION | awk '{print \$1}')\n\tsum2=\$(md5sum \${fONSMB} | awk \'{print \$1}\')\n\tif \[ \${sum1} == \${sum2} \]\n\tthen\n\t\techo \"ERROR: File $fnameBACKUPFILESCRIPTEXTENSION already exists in //\${server}/\${msshare}/\${mssubdir}\" >> /var/tmp/scriptd.out\n\t\tumount \${mountp}\n\t\trm -f $fnameBACKUPFILESCRIPTEXTENSION\n\t\texit 1\n\tfi\nfi\ncp $fnameBACKUPFILESCRIPTEXTENSION \${mountp}\${mssubdir}\nrm -f $fnameBACKUPFILESCRIPTEXTENSION\numount \${mountp}\n\nexit 0\n\n" > $scriptfile
						exec chmod +x $scriptfile
                        exec echo "f5.automated_backup iApp TMSHAPPNAME: $fname STARTING REMOTE COPY (SMB/CIFS)" >> /var/tmp/scriptd.out
                        exec logger -p local0.info "f5.automated_backup iApp TMSHAPPNAME: $fname REMOTE COPY (SMB/CIFS) STARTING"
						if { [catch {exec $scriptfile}] } {
                            exec echo "f5.automated_backup iApp TMSHAPPNAME: $fname REMOTE COPY (SMB/CIFS) FAILED (check for errors above)" >> /var/tmp/scriptd.out
                            exec logger -p local0.crit "f5.automated_backup iApp TMSHAPPNAME: $fname REMOTE COPY (SMB/CIFS) FAILED (see /var/tmp/scriptd.out for errors)"
                        } else {
                            exec echo "f5.automated_backup iApp TMSHAPPNAME: $fname REMOTE COPY (SMB/CIFS) SUCCEEDED" >> /var/tmp/scriptd.out
                            exec logger -p local0.notice "f5.automated_backup iApp TMSHAPPNAME: $fname REMOTE COPY (SMB/CIFS) SUCCEEDED"
                        }
						# Clean up local files
						exec rm -f $scriptfile
						exec rm -f BACKUPDIRECTORY/$fnameBACKUPFILESCRIPTEXTENSION
                        exec echo "f5.automated_backup iApp TMSHAPPNAME: FINISHED" >> /var/tmp/scriptd.out
                        exec logger -p local0.info "f5.automated_backup iApp TMSHAPPNAME: FINISHED"
					}
                    # Swap hostname/date format into archive filename based on iApp field
					set script [string map [list FORMAT [lindex [split $::destination_parameters__filename_format " "] 0]] $script]
                    # Swap many variables into $script; due to the curly braces used to initially set $script, any referenced variables will *not* be expanded simply by deploying the iApp.
					set script [string map [list BACKUPFILENAMEXTENSION $backup_file_name_extension BACKUPFILESCRIPTEXTENSION $backup_file_script_extension BACKUPDIRECTORY $backup_directory BACKUPCOMMAND $create_backup_command BACKUPAPPEND_PASS $create_backup_command_append_pass BACKUPAPPEND_KEYS $create_backup_command_append_keys TMSHAPPNAME $tmsh::app_name ENCRYPTEDUSERNAME $encryptedusername ENCRYPTEDPASSWORD $encryptedpassword ENCRYPTEDMSDOMAIN $encryptedmsdomain ENCRYPTEDSERVER $encryptedserver ENCRYPTEDMSSHARE $encryptedmsshare ENCRYPTEDMSSUBDIR $encryptedmssubdir ENCRYPTEDMOUNTP $encryptedmountp] $script]
				}
				else {
					set script {
                        exec echo "f5.automated_backup iApp TMSHAPPNAME: STARTED" >> /var/tmp/scriptd.out
                        exec logger -p local0.info "f5.automated_backup iApp TMSHAPPNAME: STARTED"
						# Get the hostname of the device we're running on
						set host [tmsh::get_field_value [lindex [tmsh::get_config sys global-settings] 0] hostname]
						# Get the current date and time in a specific format
						set cdate [clock format [clock seconds] -format "FORMAT"]
						# Form the filename for the backup
						set fname "${cdate}BACKUPFILENAMEXTENSION"
						# Run the 'create backup' command
                        exec echo "f5.automated_backup iApp TMSHAPPNAME: $fname GENERATING" >> /var/tmp/scriptd.out
                        exec logger -p local0.info "f5.automated_backup iApp TMSHAPPNAME: $fname GENERATING"
						BACKUPCOMMAND $fname BACKUPAPPEND_PASS BACKUPAPPEND_KEYS
                        exec echo "f5.automated_backup iApp TMSHAPPNAME: $fname SAVED LOCALLY" >> /var/tmp/scriptd.out
                        exec logger -p local0.info "f5.automated_backup iApp TMSHAPPNAME: $fname SAVED LOCALLY"
                        exec echo "f5.automated_backup iApp TMSHAPPNAME: FINISHED" >> /var/tmp/scriptd.out
                        exec logger -p local0.info "f5.automated_backup iApp TMSHAPPNAME: FINISHED"
					}
					set script [string map [list FORMAT [lindex [split $::destination_parameters__filename_format " "] 0]] $script]
					set script [string map [list BACKUPFILENAMEXTENSION $backup_file_name_extension BACKUPFILESCRIPTEXTENSION $backup_file_script_extension BACKUPDIRECTORY $backup_directory BACKUPCOMMAND $create_backup_command BACKUPAPPEND_PASS $create_backup_command_append_pass BACKUPAPPEND_KEYS $create_backup_command_append_keys TMSHAPPNAME $tmsh::app_name] $script]
		        }

		        iapp::conf create sys icall script f5.automated_backup__${tmsh::app_name} definition \{ $script \} app-service none

		        ## Get time info for setting first-occurrence on daily handler from iApp input
		        set freq $::backup_schedule__frequency_select

				#Create the handlers
				if { $freq eq "Disable" } {

				}
				elseif { $freq eq "Every X Minutes" } {
					set everyxminutes $::backup_schedule__everyxminutes_value
					set interval [expr $everyxminutes*60]
					set cdate [clock format [clock seconds] -format "%Y-%m-%d:%H:%M"]
					iapp::conf create sys icall handler periodic f5.automated_backup__${tmsh::app_name}-handler \{ \
					interval $interval \
					first-occurrence $cdate:00 \
					script f5.automated_backup__${tmsh::app_name} \}
				}
				elseif { $freq eq "Every X Hours" } {
					set everyxhours $::backup_schedule__everyxhours_value
					set interval [expr $everyxhours*3600]
					set minutes $::backup_schedule__everyxhours_min_select
					set cdate [clock format [clock seconds] -format "%Y-%m-%d:%H"]
					iapp::conf create sys icall handler periodic f5.automated_backup__${tmsh::app_name}-handler \{ \
					interval $interval \
					first-occurrence $cdate:$minutes:00 \
					script f5.automated_backup__${tmsh::app_name} \}
				}
				elseif { $freq eq "Every X Days" } {
					set everyxdays $::backup_schedule__everyxdays_value
					set interval [expr $everyxdays*86400]
					set hours [lindex [split $::backup_schedule__everyxdays_time ":"] 0]
					set minutes [lindex [split $::backup_schedule__everyxdays_time ":"] 1]
					set cdate [clock format [clock seconds] -format "%Y-%m-%d"]
					iapp::conf create sys icall handler periodic f5.automated_backup__${tmsh::app_name}-handler \{ \
					interval $interval \
					first-occurrence $cdate:$hours:$minutes:00 \
					script f5.automated_backup__${tmsh::app_name} \}
				}
				elseif { $freq eq "Every X Weeks" } {
					set everyxweeks $::backup_schedule__everyxweeks_value
					set interval [expr $everyxweeks*604800]
					set hours [lindex [split $::backup_schedule__everyxweeks_time ":"] 0]
					set minutes [lindex [split $::backup_schedule__everyxweeks_time ":"] 1]
					## Get day of week info for setting first-occurence on weekly handler from iApp input
					array set dowmap {
						Sunday 0
						Monday 1
						Tuesday 2
						Wednesday 3
						Thursday 4
						Friday 5
						Saturday 6
					}
					set sday_name $::backup_schedule__everyxweeks_dow_select
					set sday_num $dowmap($sday_name)
					set cday_name [clock format [clock seconds] -format "%A"]
					set cday_num $dowmap($cday_name)
					set date_offset [expr 86400*($sday_num - $cday_num)]
					set date_final [clock format [expr [clock seconds] + $date_offset] -format "%Y-%m-%d"]
					iapp::conf create sys icall handler periodic f5.automated_backup__${tmsh::app_name}-handler \{ \
						interval $interval \
						first-occurrence $date_final:$hours:$minutes:00 \
						script f5.automated_backup__${tmsh::app_name} \}
				}
				elseif { $freq eq "Every X Months" } {
					set everyxmonths $::backup_schedule__everyxmonths_value
					set interval [expr 60*60*24*365]
					set dom $::backup_schedule__everyxmonths_dom_select
					set hours [lindex [split $::backup_schedule__everyxmonths_time ":"] 0]
					set minutes [lindex [split $::backup_schedule__everyxmonths_time ":"] 1]
					for { set month 1 } { $month < 13 } { set month [expr $month+$everyxmonths] } {
						set cdate [clock format [clock seconds] -format "%Y-$month-$dom"]
						iapp::conf create sys icall handler periodic f5.automated_backup__${tmsh::app_name}-month_${month}-handler \{ \
						interval $interval \
						first-occurrence $cdate:$hours:$minutes:00 \
						script f5.automated_backup__${tmsh::app_name} \}
					}
				}
				elseif { $freq eq "Custom" } {
					set hours [lindex [split $::backup_schedule__custom_time ":"] 0]
					set minutes [lindex [split $::backup_schedule__custom_time ":"] 1]
					## Get day of week info for setting first-occurence on weekly handler from iApp input
					array set dowmap {
						Sunday 0
						Monday 1
						Tuesday 2
						Wednesday 3
						Thursday 4
						Friday 5
						Saturday 6
					}
					foreach sday_name $::backup_schedule__custom_dow_select {
						set sday_num $dowmap($sday_name)
						set cday_name [clock format [clock seconds] -format "%A"]
						set cday_num $dowmap($cday_name)
						set date_offset [expr 86400*($sday_num - $cday_num)]
						set date_final [clock format [expr [clock seconds] + $date_offset] -format "%Y-%m-%d"]
						iapp::conf create sys icall handler periodic f5.automated_backup__${tmsh::app_name}-handler-$sday_name \{ \
							interval 604800 \
							first-occurrence $date_final:$hours:$minutes:00 \
							script f5.automated_backup__${tmsh::app_name} \}
					}
				}

				## Automatic Pruning handler
				if { $::destination_parameters__protocol_enable eq "On this F5" } {
					set autoprune $::destination_parameters__pruning_enable
					if { $autoprune eq "Yes" } {
						set prune_conserve $::destination_parameters__keep_amount
						set today [clock format [clock seconds] -format "%Y-%m-%d"]
						set script {
							# Get the hostname of the device we're running on
							set host [tmsh::get_field_value [lindex [tmsh::get_config sys global-settings] 0] hostname]
							# Set the script filename
							set scriptfile "/var/tmp/autopruning.sh"
							# Clean, recreate, run and reclean a custom bash script that will perform the pruning
							exec rm -f $scriptfile
							exec echo -e "files_tokeep=\$(ls -t /var/local/ucs/*.ucs | head -n CONSERVE\)\nfor current_ucs_file in `ls /var/local/ucs/*.ucs` ; do\n\tcurrent_ucs_file_basename=`basename \$current_ucs_file`\n\tcheck_file=\$(echo \$files_tokeep | grep -w \$current_ucs_file_basename)\n\tif \[ \"\$check_file\" == \"\" \] ; then\n\t\trm -f \$current_ucs_file\n\tfi\ndone" > $scriptfile
							exec chmod +x $scriptfile
							exec $scriptfile
							exec rm -f $scriptfile
						}
						set script [string map [list CONSERVE $prune_conserve] $script]
						iapp::conf create sys icall script f5.automated_backup__${tmsh::app_name}_pruning definition \{ $script \} app-service none
						set cdate [clock format [clock seconds] -format "%Y-%m-%d:%H:%M"]
                        # Interval can be increased as needed if pruning every minute is problematic
						iapp::conf create sys icall handler periodic f5.automated_backup__${tmsh::app_name}_pruning-handler \{ \
						interval 60 \
						first-occurrence $cdate:00 \
						script f5.automated_backup__${tmsh::app_name}_pruning \}
					}
				}
				iapp::template end
            }
            macro {
            }
            presentation {
                section deployment_info {
                    message deployment_info_first_time "Deploying the iApp may not trigger an immediate backup."
                    message deployment_info_updates "To force the iApp to run a backup it is easiest to set the Backup Schedule to 'Every X Days', 'X equals 1', with a time earlier than right now (e.g. 01:00). This will set the first-occurrence parameter for the iCall handler to today at 01:00 which will trigger immediately (assuming the BIG-IP thinks it is after 1am). Redeploying the iApp will not trigger immediate backups unless the iCall handler is recreated which only happens if a change is made to the Backup Schedule. Simply change the time to 01:01 and redeploy with new settings to force an immediate backup attempt. When testing is complete, set the Backup Schedule to the desired ongoing schedule."
                    message deployment_info_logs "The general log for all iApps is '/var/tmp/scriptd.out'. This iApp adds run logs and errors to '/var/tmp/scriptd.out'. Additionally, this iApp sends run logs (not full error messages) to '/var/log/ltm' (compatible with BIG-IP Remote Logging configuration)."
                }
                section backup_type {
					choice backup_type_select display "xlarge" { "UCS (User Configuration Set)", "SCF (Single Configuration File)" }
					optional ( backup_type_select == "SCF (Single Configuration File)" ) {
                        message backup_help_scf "WARNING: Beware of choosing SCF file as not all configuration is included therein. Please check out SOL13408 (http://support.f5.com/kb/en-us/solutions/public/13000/400/sol13408.html) for more information."
                    }
					optional ( backup_type_select == "UCS (User Configuration Set)" ) {
						choice backup_passphrase_select display "small" { "Yes", "No" }
						optional ( backup_passphrase_select == "Yes" ) {
                            message backup_help_passphrase "WARNING: Losing the passphase will render the archives unusable. The encrypted UCS archive will be a PGP encoded file, *not* simply a tar.gz with a password on it."
							password backup_passphrase required display "large"
						}
						choice backup_includeprivatekeys display "small" { "Yes", "No" }
                        optional ( backup_includeprivatekeys == "No" ) {
                            message backup_help_privatekeys "WARNING: A UCS archive that does not contain the private keys CANNOT be used for restoring the device. It should be used for transfers to external services to whom you do not wish to disclose the private keys."
                        }
					}
				}
				section backup_schedule {
					choice frequency_select display "large" { "Disable", "Every X Minutes", "Every X Hours", "Every X Days", "Every X Weeks", "Every X Months", "Custom" }
					optional ( frequency_select == "Every X Minutes" ) {
						editchoice everyxminutes_value default "30" display "small" { "1", "2", "5", "10", "15", "20", "30", "45", "60" }
					}
					optional ( frequency_select == "Every X Hours" ) {
						editchoice everyxhours_value default "1" display "small" { "1", "2", "3", "4", "6", "12", "24" }
						choice everyxhours_min_select display "small" tcl {
							for { set x 0 } { $x < 60 } { incr x } {
								append mins "$x\n"
							}
							return $mins
						}
					}
					optional ( frequency_select == "Every X Days" ) {
						editchoice everyxdays_value default "1" display "small" { "1", "2", "3", "4", "5", "7", "14" }
						string everyxdays_time required display "medium"
					}
					optional ( frequency_select == "Every X Weeks" ) {
						editchoice everyxweeks_value default "1" display "small" { "1", "2", "3", "4", "5", "7", "14" }
						choice everyxweeks_dow_select default "Sunday" display "medium" { "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" }
						string everyxweeks_time required display "small"
					}
					optional ( frequency_select == "Every X Months" ) {
						editchoice everyxmonths_value default "1" display "small" { "1", "2", "3", "6", "12" }
						choice everyxmonths_dom_select display "small" tcl {
							for { set x 1 } { $x < 31 } { incr x } {
								append days "$x\n"
							}
							return $days
						}
						string everyxmonths_time required display "small"
					}
					optional ( frequency_select == "Custom" ) {
						multichoice custom_dow_select default {"Sunday"} display "medium" { "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" }
						string custom_time required display "small"
					}
				}
				optional ( backup_schedule.frequency_select != "Disable" ) {
					section destination_parameters {
						choice protocol_enable display "xlarge" { "On this F5", "Remotely via SCP/SFTP", "Remotely via SMB/CIFS", "Remotely via FTP" }
						optional ( protocol_enable == "Remotely via SCP/SFTP") {
							message scp_sftp_help "A connection to an SSH server can be establish using both SCP and SFTP. SCP is more efficient for copying files to a remote network destination while, for interactive sessions, the SFTP protocol offers more features. This iApp uses SCP."
                            string scp_remote_server required display "medium" validator "IpAddress"
                            message scp_remote_server_help "IMPORTANT: Check '/root/.ssh/known_hosts' on each BIG-IP (including HA peers) to ensure the Destination IP above is listed. On each BIG-IP that does not list the Destination IP, connect directly to the Destination IP using the scp or ssh command. You will be asked to verify the 'RSA key fingerprint'. Entering 'yes' will store the fingerprint in '/root/.ssh/known_hosts' and allow subsequent connections without further verification. If IP from the CLI on all BIG-IPs (including HA peers) and verify/accept the fingerprint which should add an entry to the known_hosts file."
                            choice scp_stricthostkeychecking default "Yes" display "large" { "Yes", "No (INSECURE)" }
                            optional ( scp_stricthostkeychecking == "No (INSECURE)" ) {
                                message scp_stricthostkeychecking_warning1 "WARNING: Selecting 'No (INSECURE)' will ignore certificate verification for connections this iApp makes to the server configured above. Backups could be copied to an unintended server, including one owned by a bad actor."
                            }
                            message scp_stricthostkeychecking_help1 "It is MOST SECURE to select Yes, which is the SCP/SSH default setting and which will not allow connections to unknown servers. A server is considered 'unknown' until an SSH key fingerprint has been verified, or if the destination SSL certificate changes and the fingerprint no longer matches."
                            optional ( scp_stricthostkeychecking == "Yes" ) {
                                message scp_stricthostkeychecking_help2 "Selecting 'No (INSECURE)' will ignore certificate verification for connections this iApp makes to the server configured above."
                                message scp_stricthostkeychecking_trouble1 "TROUBLESHOOTING: If the SCP script fails with a 'Host key verification failed' or 'No RSA host key is known for' error (which can viewed in /var/tmp/scriptd.out after deploying this iApp), review the IMPORTANT steps (under Destination IP) above regarding the known_hosts file to resolve the issue. Also, review additional troubleshooting notes."
                                message scp_stricthostkeychecking_trouble2 "TROUBLESHOOTING: If the SCP script fails with a 'WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!' error (which can viewed in /var/tmp/scriptd.out after deploying this iApp), the certificate on the destination server has changed. This could mean 1) The certificate was updated legitimately, or 2) There is an IP conflict and the script is connecting to the wrong server, or 3) the destination server was replaced or rebuilt and has a new certificate, or 4) a bad actor is intercepting the connection (man-in-the-middle) and the script is rightly warning you to not connect. Investigate the destination server before proceeding."
                            }
							string scp_remote_username required display "medium"
							password scp_sshprivatekey required display "large"
                            message scp_encrypted_field_storage_help "Private key must be non-encrypted and in 'OpenSSH' base64 format. As an example run 'ssh-keygen -t -b 2048 -o -a 100' from the CLI, step through the questions, and view the resulting private key (by default ssh-keygen will save the key to ~/.ssh/id_rsa)."
							message scp_encrypted_field_storage_help2 "Passwords and private keys are stored in an encrypted format. The salt for the encryption algorithm is the F5 cluster's Master Key. The master key is not shared when exporting a qkview or UCS, thus rendering your passwords and private keys safe if a backup file were to be stored off-box."
                            editchoice scp_cipher display "xlarge" { "aes128-ctr", "aes192-ctr", "aes256-ctr", "aes128-gcm@openssh.com", "chacha20-poly1305@openssh.com" }
							message scp_cipher_help "Depending on the version of F5 TMOS and the ssh configuration of the destination server, there may be no matching ciphers resulting in a 'no matching cipher found' error (which can viewed in /var/tmp/scriptd.out after deploying this iApp or it can be tested/demonstrated by attempting an scp or ssh connection from this device to the destination server). Find the word 'server' in the error and note the ciphers listed; select one of these ciphers from the list above or paste in one not listed."
							string scp_remote_directory display "medium"
						}
						optional ( protocol_enable == "Remotely via SFTP--DEPRECATED") {
							string sftp_remote_server required display "medium" validator "IpAddress"
							string sftp_remote_username required display "medium"
							password sftp_sshprivatekey required display "large"
                            message sftp_encrypted_field_storage_help "Private key must be in 'OpenSSH' base64 format. As an example run 'ssh-keygen -t -b 2048 -o -a 100' from the CLI, step through the questions, and view the resulting private key (default location is ~/.ssh/id_rsa after)."
							message sftp_encrypted_field_storage_help2 "Passwords and private keys are stored in an encrypted format. The salt for the encryption algorithm is the F5 cluster's Master Key. The master key is not shared when exporting a qkview or UCS, thus rendering your passwords and private keys safe if a backup file were to be stored off-box."
							string sftp_remote_directory display "medium"
						}
						optional ( protocol_enable == "Remotely via SMB/CIFS") {
							string smb_remote_server required display "medium" validator "IpAddress"
                            message smb_remote_server_help "Ensure this Destination IP is reachable on port 139."
							string smb_remote_domain required display "medium"
							string smb_remote_username required display "medium"
							password smb_remote_password display "medium"
                            message smb_remote_password_help "Special characters within passwords must be escaped (add a backslash before each special character as you input the password)."
							message smb_remote_password_help2 "Passwords and private keys are stored in an encrypted format. The salt for the encryption algorithm is the F5 cluster's Master Key. The master key is not shared when exporting a qkview or UCS, thus rendering your passwords and private keys safe if a backup file were to be stored off-box."
							string smb_remote_path required display "medium"
							message smb_remote_path_help "SMB share on a remote server. Do not include leading and trailing slashes. If the full share path is //SERVER/SHARE, enter SHARE in this field. If the full share path is //SERVER/PATH/SHARE, enter PATH/SHARE in this field."
							string smb_remote_directory display "medium"
							message smb_remote_directory_help "Relative path inside the SMB share to copy the file. Leave this field empty to store in root of SMB share. Include one leading slash and no trailing slashes. If the target directory is //SERVER/SHARE/PATH/DIRECTORY, enter /PATH/DIRECTORY in this field."
							string smb_local_mountdir required default "/var/tmp/cifs" display "medium"
							message smb_local_mountdir_help "Read-Write path on local F5 where SMB share will be mounted. Include one leading slash and no trailing slashes, for example /var/tmp/cifs"
						}
						optional ( protocol_enable == "Remotely via FTP") {
							string ftp_remote_server required display "medium" validator "IpAddress"
							string ftp_remote_username required display "medium"
							password ftp_remote_password display "medium"
							message ftp_encrypted_field_storage_help "Passwords and private keys are stored in an encrypted format. The salt for the encryption algorithm is the F5 cluster's Master Key. The master key is not shared when exporting a qkview or UCS, thus rendering your passwords and private keys safe if a backup file were to be stored off-box."
							string ftp_remote_directory display "medium"
						}
						editchoice filename_format display "xxlarge" tcl {
							set host [tmsh::get_field_value [lindex [tmsh::get_config sys global-settings] 0] hostname]
							set formats ""
							append formats {%Y%m%d%H%M%S_${host} => }
							append formats [clock format [clock seconds] -format "%Y%m%d%H%M%S_${host}"]
							append formats "\n"
							append formats {%Y%m%d_%H%M%S_${host} => }
							append formats [clock format [clock seconds] -format "%Y%m%d_%H%M%S_${host}"]
							append formats "\n"
							append formats {%Y%m%d_${host} => }
							append formats [clock format [clock seconds] -format "%Y%m%d_${host}"]
							append formats "\n"
							append formats {${host}_%Y%m%d%H%M%S => }
							append formats [clock format [clock seconds] -format "${host}_%Y%m%d%H%M%S"]
							append formats "\n"
							append formats {${host}_%Y%m%d_%H%M%S => }
							append formats [clock format [clock seconds] -format "${host}_%Y%m%d_%H%M%S"]
							append formats "\n"
							append formats {${host}_%Y%m%d => }
							append formats [clock format [clock seconds] -format "${host}_%Y%m%d"]
							append formats "\n"
							return $formats
						}
						message filename_format_help "You can select one, or create your own with all the [clock format] wildcards available in the tcl language, plus ${host} for the hostname. (http://www.tcl.tk/man/tcl8.6/TclCmd/clock.htm)"
						optional ( protocol_enable == "On this F5" ) {
							choice pruning_enable display "small" { "No", "Yes" }
							optional ( pruning_enable == "Yes" ) {
								editchoice keep_amount display "small" { "1", "2", "3", "4", "5", "6", "7", "8", "9", "10" }
								message pruning_help "Warning: if you decide to manually create a backupfile in the default directory, the automatic pruning will clean it if it doesn't match the 'newest X files' in that directory."
							}
						}
					}
				}
				text {
                    deployment_info "Deployment Information"
                    deployment_info.deployment_info_first_time "First Time Deployment:"
                    deployment_info.deployment_info_updates "Testing the iApp:"
                    deployment_info.deployment_info_logs "Logging:"
                    backup_type "Backup Type"
					backup_type.backup_type_select "Select the type of backup:"
					backup_type.backup_passphrase_select "Use a passphrase to encrypt the UCS archive:"
					backup_type.backup_passphrase "What is the passphrase you want to use?"
					backup_type.backup_includeprivatekeys "Include the private keys in the archives?"
					backup_type.backup_help_scf ""
					backup_type.backup_help_passphrase ""
					backup_type.backup_help_privatekeys ""
					backup_schedule "Backup Schedule"
					backup_schedule.frequency_select "Frequency:"
					backup_schedule.everyxminutes_value "Where X equals:"
					backup_schedule.everyxhours_value "Where X equals:"
					backup_schedule.everyxhours_min_select "At what minute of each X hours should the backup occur?"
					backup_schedule.everyxdays_value "Where X equals:"
					backup_schedule.everyxdays_time "At what time on each X days should the backup occur? (Ex.: 15:25)"
					backup_schedule.everyxweeks_value "Where X equals:"
					backup_schedule.everyxweeks_time "At what time on the chosen day of each X weeks should the backup occur? (e.g. 04:15, 21:30)"
					backup_schedule.everyxweeks_dow_select "On what day of each X weeks should the backup should occur:"
					backup_schedule.everyxmonths_value "Where X equals:"
					backup_schedule.everyxmonths_time "At what time on the chosen day of each X months should the backup occur? (e.g. 04:15, 21:30)"
					backup_schedule.everyxmonths_dom_select "On what day of each X months should the backup should occur:"
					backup_schedule.custom_time "At what time on each selected day should the backup occur? (e.g. 04:15, 21:30)"
					backup_schedule.custom_dow_select "Choose the days of the week the backup should occur:"
					destination_parameters "Destination Parameters"
					destination_parameters.protocol_enable "Where do the backup files need to be saved?"
                    destination_parameters.scp_sftp_help "SCP or SFTP?"
					destination_parameters.scp_remote_server "Destination IP:"
					destination_parameters.scp_remote_server_help ""
                    destination_parameters.scp_stricthostkeychecking "StrictHostKeyChecking"
                    destination_parameters.scp_stricthostkeychecking_help1 ""
                    destination_parameters.scp_stricthostkeychecking_help2 ""
                    destination_parameters.scp_stricthostkeychecking_trouble1 ""
                    destination_parameters.scp_stricthostkeychecking_trouble2 ""
                    destination_parameters.scp_stricthostkeychecking_warning1 ""
					destination_parameters.scp_remote_username "Username:"
					destination_parameters.scp_sshprivatekey "Copy/Paste the SSH private key to be used for passwordless authentication:"
					destination_parameters.scp_encrypted_field_storage_help ""
					destination_parameters.scp_encrypted_field_storage_help2 ""
					destination_parameters.scp_remote_directory "Remote directory for archive upload:"
                    destination_parameters.scp_cipher "Cipher"
                    destination_parameters.scp_cipher_help ""
					destination_parameters.sftp_remote_server "Destination IP:"
					destination_parameters.sftp_remote_username "Username:"
					destination_parameters.sftp_sshprivatekey "Copy/Paste the non-encrypted SSH private key to be used for passwordless authentication:"
					destination_parameters.sftp_encrypted_field_storage_help ""
					destination_parameters.sftp_encrypted_field_storage_help2 ""
					destination_parameters.sftp_remote_directory "Remote directory for archive upload:"
					destination_parameters.smb_remote_server "Destination IP:"
					destination_parameters.smb_remote_server_help ""
					destination_parameters.smb_remote_username "Username:"
					destination_parameters.smb_remote_domain "Domain or Hostname:"
					destination_parameters.smb_remote_password "Password:"
					destination_parameters.smb_remote_password_help ""
					destination_parameters.smb_remote_password_help2 ""
					destination_parameters.smb_remote_path "SMB/CIFS share name:"
					destination_parameters.smb_remote_path_help ""
					destination_parameters.smb_remote_directory "Target path inside SMB Share:"
					destination_parameters.smb_remote_directory_help ""
					destination_parameters.smb_local_mountdir "Local mount point:"
					destination_parameters.smb_local_mountdir_help ""
 					destination_parameters.ftp_remote_username "Username:"
					destination_parameters.ftp_remote_password "Password:"
					destination_parameters.ftp_encrypted_field_storage_help ""
					destination_parameters.ftp_remote_server "Destination IP:"
					destination_parameters.ftp_remote_directory "Set the remote directory the archive should be copied to:"
					destination_parameters.filename_format "Select the filename format:"
					destination_parameters.filename_format_help ""
					destination_parameters.pruning_enable "Activate automatic pruning?"
					destination_parameters.pruning_help ""
					destination_parameters.keep_amount "Amount of files to keep at any given time:"
				}
            }
            role-acl { admin manager resource-admin }
            run-as none
        }
    }
    description none
    ignore-verification false
    requires-bigip-version-max none
    requires-bigip-version-min 12.1.0
    requires-modules { ltm }
    signing-key none
    tmpl-checksum none
    tmpl-signature none
}