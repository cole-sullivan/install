#!/bin/sh

### OPTIONS AND VARIABLES ###

DOTFILES="https://github.com/cole-sullivan/config"
PROGS="https://raw.githubusercontent.com/cole-sullivan/install/main/progs.csv"
AURHELPER="yay"
REPOBRANCH="main"
export TERM=ansi

### FUNCTIONS ###

installpkg() {
	pacman --noconfirm --needed -S "$1" >/dev/null 2>&1
}

error() {
	# Log to stderr and exit with failure.
	printf "%s\n" "$1" >&2
	exit 1
}

welcomemsg() {
	whiptail --title "Welcome!" \
		--msgbox "Welcome to the installation script for [INSERT NAME]!\\n\\nThis script will automatically install a fully-featured Linux desktop.\\n\\n" 10 60

	whiptail --title "Important Note!" --yes-button "All ready!" \
		--no-button "Exit script" \
		--yesno "Be sure the computer you are using has current pacman updates and refreshed Arch keyrings.\\n\\nIf it does not, the installation of some programs might fail." 8 70
}

getuserandpass() {
	# Prompts user for new username an password.
	USERNAME=$(whiptail --inputbox "First, please enter a name for the user account." 10 60 3>&1 1>&2 2>&3 3>&1) || exit 1
	while ! echo "$USERNAME" | grep -q "^[a-z_][a-z0-9_-]*$"; do
		USERNAME=$(whiptail --nocancel --inputbox "Username not valid. Give a username beginning with a letter, with only lowercase letters, - or _." 10 60 3>&1 1>&2 2>&3 3>&1)
	done
	PASSWORD1=$(whiptail --nocancel --passwordbox "Enter a password for that user." 10 60 3>&1 1>&2 2>&3 3>&1)
	PASSWORD2=$(whiptail --nocancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
	while ! [ "$PASSWORD1" = "$PASSWORD2" ]; do
		unset PASSWORD2
		PASSWORD1=$(whiptail --nocancel --passwordbox "Passwords do not match.\\n\\nEnter password again." 10 60 3>&1 1>&2 2>&3 3>&1)
		PASSWORD2=$(whiptail --nocancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
	done
}

usercheck() {
	! { id -u "$USERNAME" >/dev/null 2>&1; } ||
		whiptail --title "WARNING" --yes-button "CONTINUE" \
			--no-button "No wait..." \
			--yesno "The user \`$USERNAME\` already exists on this system. This script can install for a user already existing, but it will OVERWRITE any conflicting settings/dotfiles on the user account.\\n\\This script will NOT overwrite your user files, documents, videos, etc., so don't worry about that, but only click <CONTINUE> if you don't mind your settings being overwritten.\\n\\nNote also that this script will change $USERNAME's password to the one you just gave." 14 70
}

preinstallmsg() {
	whiptail --title "Last chance!" --yes-button "Let's go!" \
		--no-button "No, nevermind!" \
		--yesno "After this, the rest of the installation will now be totally automated.\\n\\nIt will take some time, but when done, you will have a fully-configured system.\\n\\nNow just press <Let's go!> and the installation will begin!" 13 60 || {
		clear
		exit 1
	}
}

adduserandpass() {
	# Adds user `$USERNAME` with password $PASSWORD1.
	whiptail --infobox "Adding user \"$USERNAME\"..." 7 50
	useradd -m -g wheel -s /bin/zsh "$USERNAME" >/dev/null 2>&1 ||
		usermod -a -G wheel "$USERNAME" && mkdir -p /home/"$USERNAME" && chown "$USERNAME":wheel /home/"$USERNAME"
	export REPODIR="/home/$USERNAME/.local/src"
	mkdir -p "$REPODIR"
	chown -R "$USERNAME":wheel "$(dirname "$REPODIR")"
	echo "$USERNAME:$PASSWORD1" | chpasswd
	unset PASSWORD1 PASSWORD2
}

refreshkeys() {
	case "$(readlink -f /sbin/init)" in
	*systemd*)
		whiptail --infobox "Refreshing Arch Keyring..." 7 40
		pacman --noconfirm -S archlinux-keyring >/dev/null 2>&1
		;;
	*)
		whiptail --infobox "Enabling Arch Repositories for more a more extensive software collection..." 7 40
		grep -q "^\[extra\]" /etc/pacman.conf ||
			echo "[extra]
Include = /etc/pacman.d/mirrorlist-arch" >>/etc/pacman.conf
		pacman -Sy --noconfirm >/dev/null 2>&1
		pacman-key --populate archlinux >/dev/null 2>&1
		;;
	esac
}

manualinstall() {
	# Installs $1 manually. Used only for AUR helper here.
	# Should be run after repository directory is created and var is set.
	pacman -Qq "$1" && return 0
	whiptail --infobox "Installing \"$1\" manually." 7 50
	sudo -u "$USERNAME" mkdir -p "$REPODIR/$1"
	sudo -u "$USERNAME" git -C "$REPODIR" clone --depth 1 --single-branch \
		--no-tags -q "https://aur.archlinux.org/$1.git" "$REPODIR/$1" ||
		{
			cd "$REPODIR/$1" || return 1
			sudo -u "$USERNAME" git pull --force origin master
		}
	cd "$REPODIR/$1" || exit 1
	sudo -u "$USERNAME" \
		makepkg --noconfirm -si >/dev/null 2>&1 || return 1
}

maininstall() {
	# Installs all needed programs from main repo.
	whiptail --title "Installation" --infobox "Installing \`$1\` ($N of $TOTAL). $1 $2" 9 70
	installpkg "$1"
}

gitmakeinstall() {
	PROGNAME="${1##*/}"
	PROGNAME="${PROGNAME%.git}"
	DIR="$REPODIR/$PROGNAME"
	whiptail --title "Installation" \
		--infobox "Installing \`$PROGNAME\` ($N of $TOTAL) via \`git\` and \`make\`. $(basename "$1") $2" 8 70
	sudo -u "$USERNAME" git -C "$REPODIR" clone --depth 1 --single-branch \
		--no-tags -q "$1" "$DIR" ||
		{
			cd "$DIR" || return 1
			sudo -u "$USERNAME" git pull --force origin master
		}
	cd "$DIR" || exit 1
	make >/dev/null 2>&1
	make install >/dev/null 2>&1
	cd /tmp || return 1
}

aurinstall() {
	whiptail --title "Installation" \
		--infobox "Installing \`$1\` ($N of $TOTAL) from the AUR. $1 $2" 9 70
	echo "$AURINSTALLED" | grep -q "^$1$" && return 1
	sudo -u "$USERNAME" $AURHELPER -S --noconfirm "$1" >/dev/null 2>&1
}

pipinstall() {
	whiptail --title "Installation" \
		--infobox "Installing the Python package \`$1\` ($N of $TOTAL). $1 $2" 9 70
	[ -x "$(command -v "pip")" ] || installpkg python-pip >/dev/null 2>&1
	yes | pip install "$1"
}

installationloop() {
	([ -f "$PROGS" ] && cp "$PROGS" /tmp/progs.csv) ||
		curl -Ls "$PROGS" | sed '/^#/d' >/tmp/progs.csv
	TOTAL=$(wc -l </tmp/progs.csv)
	AURINSTALLED=$(pacman -Qqm)
	while IFS=, read -r TAG PROGRAM COMMENT; do
		N=$((N + 1))
		echo "$COMMENT" | grep -q "^\".*\"$" &&
			COMMENT="$(echo "$COMMENT" | sed -E "s/(^\"|\"$)//g")"
		case "$TAG" in
		"A") aurinstall "$PROGRAM" "$COMMENT" ;;
		"G") gitmakeinstall "$PROGRAM" "$COMMENT" ;;
		"P") pipinstall "$PROGRAM" "$COMMENT" ;;
		*) maininstall "$PROGRAM" "$COMMENT" ;;
		esac
	done </tmp/progs.csv
}

putgitrepo() {
	# Downloads a gitrepo $1 and places the files in $2 only overwriting conflicts
	whiptail --infobox "Downloading and installing config files..." 7 60
	[ -z "$3" ] && branch="main" || branch="$REPOBRANCH"
	DIR=$(mktemp -d)
	[ ! -d "$2" ] && mkdir -p "$2"
	chown "$USERNAME":wheel "$DIR" "$2"
	sudo -u "$USERNAME" git -C "$REPODIR" clone --depth 1 \
		--single-branch --no-tags -q --recursive -b "$branch" \
		--recurse-submodules "$1" "$DIR"
	sudo -u "$USERNAME" cp -rfT "$DIR" "$2"
}

enrollfingerprint() {
	TEMPOUTPUT=$(mktemp)
 	PROGRESSFILE=$(mktemp)
  	MAXATTEMPTS=9
   	echo 0 > "$PROGRESSFILE"
    	(
		fprintd-enroll "$USERNAME" | tee "$TEMPOUTPUT" |
       		while IFS= read -r LINE; do
	 		if [[ "$LINE" == *"Enroll result: enroll-stage-passed"* ]]; then
    				CURRENT=$(cat "$PROGRESSFILE")
				NEWPROGRESS=$((CURRENT + 100/MAXATTEMPTS))
    				echo "$NEWPROGRESS" > "$PROGRESSFILE"
				echo "$NEWPROGRESS"
    			elif [[ "$LINE" == *"Enroll result: enroll-completed"* ]]; then
       				echo "100"
	   		fi
      		done
	) | whiptail --gauge "Enrolling fingerprint. Repeatedly scan your right index finger until the bar reaches 100%." 10 70 0

 	if grep -q "Enroll result: enroll-completed" "$TEMPOUTPUT"; then
  		whiptail --title "Enrollment complete!" --msgbox "Successfully enrolled fingerprint!" 10 60
    	else
     		ERRORMSG=$(grep "ERROR" "$TEMPOUTPUT" | head -1)
       		if [ -z "$ERRORMSG" ]; then
	 		ERRORMSG="Enrollment did not complete successfully."
    		fi
      		whiptail --title "Enrollment failed..." --msgbox "Failed to enroll fingerprint:\\n\\n$ERRORMSG" 10 60
	fi
	rm -f $TEMPOUTPUT $PROGRESSFILE
}

finalize() {
	whiptail --title "All done!" \
		--msgbox "Provided there were no hidden errors, the script completed successfully and all the programs and configuration files should be in place.\\n\\nSelect <OK> to reboot the machine.\\n\\n" 13 80
}

### THE ACTUAL SCRIPT ###

### This is how everything happens in an intuitive format and order.

# Check if user is root on Arch distro. Install whiptail.
pacman --noconfirm --needed -Sy libnewt ||
	error "Are you sure you're running this as the root user, are on an Arch-based distribution, and have an internet connection?"

# Welcome user and pick dotfiles.
welcomemsg || error "User exited."

# Get and verify username and password.
getuserandpass || error "User exited."

# Give warning if user already exists.
usercheck || error "User exited."

# Last chance for user to back out before install.
preinstallmsg || error "User exited."

### The rest of the script requires no user input.

# Refresh Arch keyrings.
refreshkeys ||
	error "Error automatically refreshing Arch keyring. Consider refreshing manually."

for x in curl ca-certificates base-devel git ntp zsh; do
	whiptail --title "Installation" \
		--infobox "Installing \`$x\` which is required to install and configure other programs." 8 70
	installpkg "$x"
done

whiptail --title "Installation" \
	--infobox "Synchronizing system time to ensure successful and secure installation of software..." 8 70
ntpd -q -g >/dev/null 2>&1

adduserandpass || error "Error adding username and/or password."

[ -f /etc/sudoers.pacnew ] && cp /etc/sudoers.pacnew /etc/sudoers # Just in case

# Allow user to run sudo without password. Since AUR programs must be installed
# in a fakeroot environment, this is required for all builds with AUR.
trap 'rm -f /etc/sudoers.d/install-aur-temp' HUP INT QUIT TERM PWR EIT
echo "%wheel ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers.d/install-aur-temp

# Make pacman colorful, concurrent downloads and Pacman eye-candy.
grep -q "ILoveCandy" /etc/pacman.conf || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf
sed -Ei "s/^#(ParallelDownloads).*/\1 = 5/;/^#Color$/s/#//" /etc/pacman.conf

# Use all cores for compilation.
sed -i "s/-j2/-j$(nproc)/;/^#MAKEFLAGS/s/^#//" /etc/makepkg.conf

manualinstall $AURHELPER || error "Failed to install AUR helper."

# Make sure .*-git AUR packages get updated automatically.
$AURHELPER -Y --save --devel

# The command that does all the installing. Reads the progs.csv file and
# installs each needed program the way required. Be sure to run this only after
# the user has been created and has privileges to run sudo without a password
# and all build dependencies are installed.
installationloop

# Install the dotfiles in the user's home directory, but remove .git dir and
# other unnecessary files.
putgitrepo "$DOTFILES" "/home/$USERNAME" "$REPOBRANCH"
rm -rf "/home/$USERNAME/.git/" "/home/$USERNAME/README.md"

# Install greetd configuration in the correct spot and enable greetd.service
rm -f /etc/greetd/config.toml
echo "user = \"$USERNAME\"" >> /home/$USERNAME/tmp/config.toml
mv /home/$USERNAME/tmp/config.toml /etc/greetd/config.toml
systemctl enable greetd.service

# Most important command! Get rid of the beep!
rmmod pcspkr
echo "blacklist pcspkr" >/etc/modprobe.d/nobeep.conf

# Make zsh the default shell for the user.
chsh -s /bin/zsh "$USERNAME" >/dev/null 2>&1
sudo -u "$USERNAME" mkdir -p "/home/$USERNAME/.cache/zsh/"

# dbus UUID must be generated for Arch runit.
dbus-uuidgen >/var/lib/dbus/machine-id

# Enable PipeWire and WirePlumber
systemctl enable --user --now pipewire wireplumber pipewire-pulse

# Allow wheel users to sudo with password and allow several system commands
# (like `shutdown` to run without password).
echo "%wheel ALL=(ALL:ALL) ALL" >/etc/sudoers.d/00-wheel-can-sudo
echo "%wheel ALL=(ALL:ALL) NOPASSWD: /usr/bin/shutdown,/usr/bin/reboot,/usr/bin/systemctl suspend,/usr/bin/mount,/usr/bin/umount,/usr/bin/pacman -Syu,/usr/bin/pacman -Syyu,/usr/bin/pacman -Syyu --noconfirm,/usr/bin/loadkeys,/usr/bin/pacman -Syyuw --noconfirm,/usr/bin/pacman -S -u -y --config /etc/pacman.conf --,/usr/bin/pacman -S -y -u --config /etc/pacman.conf --" >/etc/sudoers.d/01-cmds-without-password
echo "Defaults editor=/usr/bin/nvim" >/etc/sudoers.d/02-visudo-editor
mkdir -p /etc/sysctl.d
echo "kernel.dmesg_restrict = 0" > /etc/sysctl.d/dmesg.conf

# If user has a fingerprint reader, install fprintd and enroll fingerprint
if whiptail --title "Fingerprint" --yesno "Do you have a fingerprint reader?" 10 60; then
	installpkg fprintd
	enrollfingerprint
	rm -f /etc/pam.d/system-local-login /etc/pam.d/sudo
	mv /home/$USERNAME/tmp/system-local-login /etc/pam.d/system-local-login
	mv /home/$USERNAME/tmp/sudo /etc/pam.d/sudo
fi

# Cleanup
rm -f /etc/sudoers.d/install-aur-temp
rm -rf /home/$USERNAME/tmp

# Last message! Install complete!
finalize
reboot
