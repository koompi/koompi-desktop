# The strip along the top

It is always there, and everything the desktop wants to tell you is on it.

## The left end

The KOOMPI star opens the left-hand panel, which holds the assistant.
`Super+A` does the same.

Next to it is the program you are in: its name, and underneath, what it has open.
With nothing open it reads Desktop, and nothing under it.
Click that name for the window's own actions.
When you start a program, its icon and name appear there at once with "Opening…" under them, and pulse until its window arrives.
It gives up after eight seconds, so a program that never shows a window does not hold the strip.
To the right of it, the program's menus - File, Edit, View - if it has them.
Dolphin, Okular, Konsole and Ark put them there when you open them from Search, from the page of everything installed, or with their key.
Some other programs keep theirs inside their own window instead.

Scroll anywhere on the left half of the strip to change screen brightness.

## The middle

Your desks.
Scroll to step through them, right-click for the overview.

## The right end

The right end always reads in the same order.
From left to right:

- the tray icons of running programs, then the media that is playing, agent usage and a running pomodoro, each only while it has something to show
- small lights for things that are on and easy to forget, each only while it is on: a red dot while the screen is being recorded, a microphone while a program is listening, a crossed microphone or speaker while one is muted, a coffee cup for **Keep awake**, a moon for **Night light**, a circle with a bar for **Do Not Disturb**, a red microphone while dictation is listening
- a glyph with the number of updates waiting, which you can click to install them
- which keyboard layout is live, English or Khmer
- Wi-Fi
- the battery, as a glyph with its percentage beside it, on a laptop
- the Control Center glyph, a row of sliders
- the clock

Each of these is its own target.
A click on a light turns that mode off or undoes the mute, and a click on the update glyph opens its list.
Nothing else on the strip opens a panel: **the Control Center glyph** opens the Control Center, with the switches and sliders, and **the clock** opens the Notification Center.
Each is drawn pressed in while its panel is open, and opening one closes the other.

Unread notifications show as a small dot on the clock.
Do Not Disturb is its own light, and the dot stays away while it is on.

Hover the clock for the date and your next tasks.
The time the computer has been on is in Settings under About.

The strip stays readable on any wallpaper: the text is dimmed on a screen that is not the one you are working on, but never below a clear contrast against even a white or black picture behind it.
If you turn the strip's background off in Settings, that guarantee goes with it.

Scroll anywhere on the right half of the strip to change the volume.

## Notifications

A notification arrives as a card in the top right and goes away on its own.

| Keys | Does |
| --- | --- |
| `Super+,` | dismiss the newest card |
| `Super+Shift+,` | dismiss all of them |
| `Super+Alt+,` | do what the newest card is offering, then dismiss it |
| `Super+Shift+Alt+,` | open the history in the right-hand panel |

Nothing dismissed is lost.
The right-hand panel keeps the history either way.

Opening the Notification Center from the clock marks everything read once it has stayed open for a second, so a panel you open and close at once leaves the dot alone.

For a quiet hour:

```sh
koompi toggle silent
```

No toasts appear while it is on, and they are all still in the history when you turn it off.

## Hovering, and the four popups

Hover a widget on the right and it opens a small panel with the detail behind it.

Four of them can also be opened from the keyboard, counting from the left as the bar draws them:

| Keys | Opens |
| --- | --- |
| `Super+Ctrl+1` | agent usage |
| `Super+Ctrl+2` | battery |
| `Super+Ctrl+3` | the pomodoro timer |
| `Super+Ctrl+4` | the clock |

The same key again closes it, and so does Escape.

## Turning it off, and moving it

`Super+J` hides the strip and brings it back.

`Ctrl+Super+P` switches between the two panel families the desktop ships, which look and behave differently.
Settings can also stand the strip on its end, as a bar down the side of the screen, or move it to the bottom.
