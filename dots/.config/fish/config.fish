# Commands to run in interactive sessions can go here
if status is-interactive
    # No greeting
    set fish_greeting

    # Use starship
    function starship_transient_prompt_func
        starship module character
    end
    if test "$TERM" != "linux"
        starship init fish | source
        enable_transience
    end
    
    # Colors, except in a terminal with a KOOMPI scheme of its own (Konsole,
    # wezterm), which the wallpaper palette would repaint. Asked of the
    # parent of the session leader, not the environment: a terminal's
    # variables reach everything started from a shell inside it.
    set -l leader (ps -o sid= -p $fish_pid 2>/dev/null | string trim)
    set -l terminal (ps -o comm= -p (ps -o ppid= -p $leader 2>/dev/null | string trim) 2>/dev/null)
    if test -f ~/.local/state/quickshell/user/generated/terminal/sequences.txt
        and not contains -- "$terminal" konsole wezterm-gui
        cat ~/.local/state/quickshell/user/generated/terminal/sequences.txt
    end

    # Aliases
    # kitty doesn't clear properly so we need to do this weird printing
    alias clear "printf '\033[2J\033[3J\033[1;1H'"
    alias celar "printf '\033[2J\033[3J\033[1;1H'"
    alias claer "printf '\033[2J\033[3J\033[1;1H'"
    alias pamcan pacman
    alias q 'qs -c koompi'
    if test "$TERM" != "linux"
        alias ls 'eza --icons'
    end
    if test "$TERM" = "xterm-kitty"
        alias ssh 'kitten ssh'
    end
end
