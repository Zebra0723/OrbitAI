#!/bin/bash
# The catch-all: anything the catalog in lib/system.sh doesn't cover gets
# written by Claude Code as a one-line command.
#
# Two rules make this safe enough to leave on. Nothing runs without being
# read back to you first - you hear the plain-English summary and say yes -
# and a denylist refuses whole categories outright, so a misunderstanding
# can't reach for sudo or the disk utility no matter how the sentence was
# phrased.
#
# The list is checked by lib/nlu_claude.sh, which is the one thing that
# produces these commands. It used to live beside a planner of its own
# that nothing had called since; the list was therefore never consulted,
# and neither was the switch that is supposed to turn all of this off.

# Categories Orbit will not run, whatever it was asked.
#
# Deliberately blunt. This is not a sandbox and cannot be made into one -
# it is a list of things a voice assistant has no business doing, so that
# a half-heard sentence never gets as far as being offered.
_freeform_refused() {
  local cmd
  cmd="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"

  # Becoming somebody else, or asking the system to.
  case "$cmd" in
    *sudo*|*"su -"*|*doas*|\
    *"administrator privileges"*|*"with prompt"*|*"do shell script"*)
      return 0 ;;
  esac

  # Deleting things. Any recursive remove, however the flags are spelt.
  case "$cmd" in
    *"rm -"*r*|*"rm --recursive"*|*"rm -"*f*|*"rm --force"*|\
    *"find "*-delete*|*"find "*-exec\ rm*|*srm*|*shred*|\
    *"mv "*"/dev/null"*|*truncate*|*"defaults delete"*)
      return 0 ;;
  esac

  # Disks and filesystems.
  case "$cmd" in
    *diskutil*|*mkfs*|*newfs*|*fdisk*|*"dd if="*|*"dd of="*|*/dev/disk*|\
    *"chmod -r"*|*"chown -r"*|*"chflags -r"*|*hdiutil*|*asr*)
      return 0 ;;
  esac

  # Secrets, and the record of what was done.
  case "$cmd" in
    *"security dump-keychain"*|*"security find-generic"*|\
    *"security find-internet"*|*"security export"*|\
    *"history -c"*|*".bash_history"*|*".zsh_history"*)
      return 0 ;;
  esac

  # Anything that outlives the command: agents, jobs, login items,
  # shell startup files.
  case "$cmd" in
    *launchctl*|*launchagents*|*launchdaemons*|*crontab*|*"at now"*|\
    *".zshrc"*|*".bashrc"*|*".zprofile"*|*".bash_profile"*|\
    *"login item"*|*"startup item"*)
      return 0 ;;
  esac

  # Fetching code and running it, in either order.
  case "$cmd" in
    *"| sh"*|*"|sh"*|*"| bash"*|*"|bash"*|*"| zsh"*|*"|zsh"*|\
    *curl*|*wget*|*"nc "*|*netcat*|*"ssh "*|*"scp "*|*sftp*|*rsync*|\
    *"base64 -d"*|*"base64 --decode"*|*eval*|*xargs*|\
    *"python -c"*|*"python3 -c"*|*"perl -e"*|*"ruby -e"*|*"osascript -e"*"do shell"*)
      return 0 ;;
  esac

  # Writing over the system, or over anything by redirection into a path
  # that is not obviously the user's own scratch.
  case "$cmd" in
    *">/etc"*|*"> /etc"*|*">>/etc"*|*">> /etc"*|\
    *"> /system"*|*"> /library"*|*"> /usr"*|*"> /bin"*|*"> /sbin"*|\
    *"tee /etc"*|*"tee /system"*|*"tee /usr"*)
      return 0 ;;
  esac

  # Ending the session, or the machine.
  case "$cmd" in
    *"shutdown -"*|*halt*|*reboot*|*"killall -9"*|*"pkill -9"*|\
    *"kill -9 -1"*)
      return 0 ;;
  esac

  # Losing work that is not a file.
  case "$cmd" in
    *"git push"*--force*|*"git push -f"*|*"git reset --hard"*|\
    *"git clean"*-*f*)
      return 0 ;;
  esac

  # A one-liner is the contract; anything multi-line is out of scope.
  case "$cmd" in
    *$'\n'*) return 0 ;;
  esac
  return 1
}
