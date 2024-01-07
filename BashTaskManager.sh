#!/bin/bash

readonly REGEX='^[0-9]+$'
readonly MAX_ERROR_COUNTER=3
readonly ACTIVE_TASKS_PATH="./Tasks"
readonly CONFIG_PATH="./_configs"
readonly SETTINGS_FILE="_settings"
readonly TIMETABLE_FILE="_timetable"
readonly NOTIFICATION_SENDER_FILE="NotificationSender.ps1"
readonly TASK_NUMBER_SETTING="TASK_NUMBER"
readonly JOB_ID_SETTING="JOB_ID"
	
declare	-A tasks=()
declare -i error_counter=0
declare -i selection=-1

function __is_task_manager_installed() {
	local -i is_installed=1;
	
	if [[ -d $CONFIG_PATH ]] 
		then
			if [[ (-f $CONFIG_PATH"/"$NOTIFICATION_SENDER_FILE) && 
				(-f $CONFIG_PATH"/"$TIMETABLE_FILE) && 
				(-f $CONFIG_PATH"/"$TIMETABLE_FILE) ]]
			then
				is_installed=0
			else 
				is_installed=1
			fi
		else
			is_installed=1
	fi
	
	echo $is_installed
}

function __load_all_tasks() {
	local path=$1
	
	if [[ -d $path ]] 
	then
		while IFS= read -r -d $'\0'; do
			local -l task=("$REPLY")
			task=$(echo $(echo $task | cut -d '/' -f 3) | sed 's/^\.\///g')
			local -i task_number=$(echo $task | cut -d '_' -f 2)
			
			tasks[$task_number]=$task
		done < <(find $path -maxdepth 1 -mindepth 1 -regex '^.*task_[0-9]+$' -print0)
	fi
	
	echo "Total tasks: ${#tasks[@]}"
}

function __get_setting_value() {
	local -u setting_name=$1
	local -i setting_value=0
	
	while IFS= read -r line
	do
		local -u name=$(echo $line | cut -d '|' -f 1)
		setting_value=$(echo $line | cut -d '|' -f 2)
		
		if [[ $setting_name == $name ]] 
		then
			break
		fi
	done < $CONFIG_PATH"/"$SETTINGS_FILE
	
	echo $setting_value
}

function __update_setting() {
	local -u setting_name=$1
	local -i new_value=$2
	local -i value=$(__get_setting_value $setting_name)
	local -u search_text="$setting_name|$value"
	local -u new_text="$setting_name|$new_value"
	
	sed -i "s/$search_text/$new_text/" $CONFIG_PATH"/"$SETTINGS_FILE
}

function __delete_expired_task() {
	local -l task_to_delete=$1
	local -i line_number=0
				
	while IFS= read -r line
	do
		local -l task=$(echo $line | cut -d '|' -f 1)
		line_number+=1
		
		if [[ $task == $task_to_delete ]] 
		then
			sed -i $line_number"d" $CONFIG_PATH"/"$TIMETABLE_FILE
			rm "$ACTIVE_TASKS_PATH/$task_to_delete"
			
			break
		fi
	done < $CONFIG_PATH"/"$TIMETABLE_FILE
}

function add_new_task() {
	error_counter=0
	
	read -p "Title: " title
	read -p "Details: " details
	
	while [ $error_counter -lt $MAX_ERROR_COUNTER ]
	do
		read -p "Datetime (yyyy-MM-dd hh:mm): " datetime
		if date -d "$datetime" "+%Y-%m-%d %H:%M" >/dev/null 2>&1; then
			local datetime_now=$(date "+%Y-%m-%d %H:%M")

			if [[ $(date -d "$datetime" +"%Y%m%d%H%M") > $(date -d "$datetime_now" +"%Y%m%d%H%M") ]]
			then
				error_counter=0
			
				while [ $error_counter -lt $MAX_ERROR_COUNTER ]
				do
					read -p "Number of days to repeat: " days_repeat
					
					if [[ !($days_repeat =~ $REGEX) || ($days_repeat -lt 0) ]]
					then
						echo "Invalid '$days_repeat' number of days to repeat the task. Please, try again!"
						error_counter+=1
					else
						error_counter=0
						break
					fi
				done
				
				break
			else 
				echo "Datetime must be bigger then the current datetime '$datetime_now'"
				error_counter+=1
			fi
		else
			echo "Invalid '$datetime datetime value. Please, try again!"
			error_counter+=1
		fi
	done
	
	if [[ $error_counter -eq 0 ]]
	then
		echo "Title: $title"
		echo "Details: $details"
		echo "Datetime: $datetime"
		echo "Repeat: $days_repeat days"
		
		while [ $error_counter -lt $MAX_ERROR_COUNTER ]
		do
			read -p "Save task (Y/N)?" should_save_task
			case $should_save_task in
				[yY]) mkdir -p $ACTIVE_TASKS_PATH
					local task_number=$(($(__get_setting_value $TASK_NUMBER_SETTING)+1))
					local new_task_name="task_"$task_number
					local -l created_datetime=$(date "+%Y-%m-%d %H:%M")
					
					echo "$new_task_name|$datetime|$days_repeat" >> $CONFIG_PATH"/"$TIMETABLE_FILE
					echo "$title|$details|$datetime|$days_repeat|$created_datetime" > $new_task_name
					mv $new_task_name $ACTIVE_TASKS_PATH
					
					__update_setting $TASK_NUMBER_SETTING $task_number
					echo "Task saved!"
					
					break;;
				[nN]) echo "Task not saved!"
					break;;
				*) echo "Invalid input!"
					error_counter+=1;;
			esac
		done
	fi
}

function show_task() {
	error_counter=0
	__load_all_tasks $ACTIVE_TASKS_PATH
	
	if [[ ${#tasks[@]} -gt 0 ]]
	then
		while [ $error_counter -lt $MAX_ERROR_COUNTER ]
		do
			echo "All tasks: ${tasks[*]}"
			read -p "Enter number to read task: " read_task_number
			
			if [[ ${tasks[$read_task_number]} ]]
			then
				local file_content=$(<$ACTIVE_TASKS_PATH'/task_'$read_task_number)
				echo "Title: $(echo $file_content | cut -d '|' -f 1)"
				echo "Details: $(echo $file_content | cut -d '|' -f 2)"
				echo "Datetime: $(echo $file_content | cut -d '|' -f 3)"
				echo "Repeat: $(echo $file_content | cut -d '|' -f 4) days"
				echo "Created: $(echo $file_content | cut -d '|' -f 5)"
			else 
				echo "No such task found!"
			fi
		
			read -p "Read more tasks (Y/N)?" should_read_task
			case $should_read_task in
				[yY]) error_counter=0;;
				[nN]) break;;
				*) echo "Invalid input!"
					error_counter+=1;;
			esac
		done
	fi
}

function delete_task() {
	local -i line_number=0
	error_counter=0
	
	__load_all_tasks $ACTIVE_TASKS_PATH
	
	if [[ ${#tasks[@]} -gt 0 ]]
	then
		while [ $error_counter -lt $MAX_ERROR_COUNTER ]
		do
			echo "${tasks[*]}"
			read -p "Enter number to delete task: " read_task_number
			
			if [[ ${tasks[$read_task_number]} ]]
			then
				local -l task_to_delete=${tasks[$read_task_number]}
				__delete_expired_task $task_to_delete
				
				echo "Task deleted!"
			else 
				echo "No such task found!"
			fi
		
			read -p "Delete more tasks (Y/N)?" delete_more
			case $delete_more in
				[yY]) error_counter=0;;
				[nN]) break;;
				*) echo "Invalid input!"
					error_counter+=1;;
			esac
		done
	fi
}

# Starts the scheduler in background
function __start_scheduler() {
	while true
	do
		sleep 10s
		local -i line_number=0
		
		while IFS= read -r line
		do
			local datetime_now=$(date "+%Y-%m-%d %H:%M")
			local task_name=$(echo $line | cut -d '|' -f 1)
			local task_datetime=$(date -d "$(echo $line | cut -d '|' -f 2)" "+%Y-%m-%d %H:%M")
			local -i task_days_repeat=$(echo $line | cut -d '|' -f 3)
			line_number+=1
			
			if [[ ($task_datetime < $datetime_now) || ($task_datetime == $datetime_now) ]]
			then
				local -i task_number=$(echo $task_name | cut -d '_' -f 2)
				local file_content=$(<$ACTIVE_TASKS_PATH'/task_'$task_number)
				local title=$(echo $file_content | cut -d '|' -f 1)
				local details=$(echo $file_content | cut -d '|' -f 2)
				local datetime_created=$(echo $file_content | cut -d '|' -f 5)
				
				local next_date=$(date -d "$task_datetime next day" "+%Y-%m-%d %H:%M")
				task_days_repeat=$((task_days_repeat - 1))
				
				if [[ $task_days_repeat -lt 0 ]]
				then
					__delete_expired_task "task_"$task_number
				else
					sed -i $line_number"s/.*/$task_name|$next_date|$task_days_repeat/" $CONFIG_PATH"/"$TIMETABLE_FILE
				fi
							
				powershell -ExecutionPolicy Bypass -File $CONFIG_PATH"/"$NOTIFICATION_SENDER_FILE "$title" "$details" "$datetime_created"
			fi
		done < $CONFIG_PATH"/"$TIMETABLE_FILE
		
		wait
	done
}

function install_task_manager() {
	local -i is_installed=$(__is_task_manager_installed)

	if [[ $is_installed -eq 1 ]]
	then
		mkdir -p $CONFIG_PATH
		
		echo -e '$title=$args[0]\n$details=$args[1]\n$datetime_created=$args[2]\nmsg * "Title: $title\nDetails: $details\nCreated on: $datetime_created"\n' > $NOTIFICATION_SENDER_FILE
		mv $NOTIFICATION_SENDER_FILE $CONFIG_PATH
		
		touch $TIMETABLE_FILE
		mv $TIMETABLE_FILE $CONFIG_PATH
		
		echo -e "$TASK_NUMBER_SETTING|0\n$JOB_ID_SETTING|0" > $CONFIG_PATH"/"$SETTINGS_FILE
		
		__start_scheduler &
		__update_setting $JOB_ID_SETTING $!
		
		echo "Setup completed successfully!"
	else
		echo "'Bash Task Manager' has already been installed!"
	fi
}

function uninstall_task_manager() {
	local -i job_id=$(__get_setting_value $JOB_ID_SETTING)
	kill $job_id
	
	rm -rf $ACTIVE_TASKS_PATH
	rm -rf $CONFIG_PATH
	
	echo "'Bash Task Manager' successfully uninstalled!"
}

# Checks if the Bash Task Manager was installed first
# before executing any command (for example adding a new task)
function execute_func_command() {
	local func_command=$1
	local -i is_task_manager_installed=$(__is_task_manager_installed);
	
	if [[ $is_task_manager_installed -eq 0 ]]
	then
		$func_command
	else
		echo "'Bash Task Manager' must be installed first!"
	fi
}

# Restarts the scheduler running in background
# if the process was killed (for example when the PC was shut down)
function __init() {
	local -i job_id=0
	local -i is_installed=$(__is_task_manager_installed)
	
	if [[ $is_installed -eq 0 ]]
	then
		job_id=$(__get_setting_value $JOB_ID_SETTING)
	
		if !(ps -p $job_id >&-); then
			__start_scheduler &
			__update_setting $JOB_ID_SETTING $!
		fi
	fi
}

__init

# Catch Ctrl + C
trap 'printf "\nPress 0 to quit!"' SIGINT

clear
while [ $selection -ne 0 ]
do 

cat << EOF
## Wellcome to Bash Task Manager ##
Please Select:

1. Install Bash Task Manager
2. Add new task
3. Show task
4. Delete task
5. Uninstall Bash Task Manager
0. Quit

EOF
echo -n 'Enter selection [0-5]: '
read -r selection

	case $selection in
		0) exit 0;;
		1) install_task_manager;;
		2) execute_func_command add_new_task;;
		3) execute_func_command show_task;;
		4) execute_func_command delete_task;;
		5) execute_func_command uninstall_task_manager;;
		*) echo "Invalid entry!" >&2;;
	esac
	printf "\n"
done

