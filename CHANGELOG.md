# DadMode changes

## 1.25.0

- **Your status, quests, gear and bag contents are now private.** They are whispered to the guide who asked, so no other computer in the party receives them. Before, they went to the whole party and other DadMode users' addons simply ignored them.
- If a whisper does not get through, the guide's addon notices after a few seconds and asks once more the old way, so the window never stays empty.
- Two guides asking at the same moment each get their own answer.
- Under the hood the addon is now one file per job (23 small files instead of a few large ones). Nothing you can see changes from that.

## 1.24.0

Nothing you can see changes in this version.

- The addon is now made of six files instead of one very large one. That makes future changes safer.

## 1.23.0

For guides:

- The buttons now carry the name of the one you guide: "Call Olaf", "Waypoint for Olaf", "How is Olaf doing". They no longer say "dad".
- A new line on the guide bar shows who you are guiding.
- With two or more people to guide in the party, click that line to choose one. Calls and waypoints then go only to that person. "Everyone" sends to all.

Other:

- `/dadmode testbox` shows the Yes / No box with a made-up guide, so you can look at it without a second player.
- **My guides** is now listed under DadMode in the options from the start. In 1.22.0 it only appeared after pressing the Open button.
- Two setting names that were cut off on the options page are shorter now.

## 1.22.0

The one being guided now decides who may guide them.

- The first time somebody tries to guide you, a box asks: "Anna wants to be your guide. Yes / No". Until you say yes, that person sees nothing of yours and cannot call you.
- New page in the game options, under DadMode: **My guides**. It lists who you approved or refused, and has switches for what your guides may see (status, gold, quests, gear) and do (call you, set waypoints, tell you to put on gear). Everything is on unless you switch it off.
- A guide who is not approved yet, or who asks for something that is switched off, is told so in plain words.
- If you used DadMode before this version, the people you had already picked are approved by themselves. Nothing changes for you.

## 1.21.3

- The DadMode logo now shows in the game's addon list instead of a question mark.

## 1.21.2

First public version, for WoW Forever.

For the player being guided:

- Big arrows to the party members you pick, with distance.
- A quiet warning when you drift far away.
- A green follow button, and calls from your guides.
- A red arrow to a waypoint a guide set, with zeppelin and boat steps when it is far away.

For guides:

- A bar with calls, a waypoint, an icon over your head and a beam on the ground.
- The "How is dad doing" window: overview, quests with search, missing quests, dungeon quests, gear.
- Item tooltips compare against the gear of the one you guide, and drops that look like an upgrade get a chat line.
- Gear in their bags compared with what they wear, and "tell him to put it on".
- Warnings on the bar: dead, bags full, broken gear, talent points, older DadMode version.
