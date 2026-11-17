# DadMode changes

## 1.35.0

- **Right click a talent to take back what you pointed at.** The pointing goes away on your Talents tab, and his screen says you took it back. Then you can point at another one right away.
- He needs this version too for the text on his screen to go away.

## 1.34.0

- **A Quest list button on the guide bar.** It shows the small quest list and puts it away again. Shown with the button, the list stays on the screen also when there is nothing to follow yet, and says how it fills.
- `/dadmode tracker` does the same as the button.

## 1.33.0

- **The Talents tab now works on WoW Forever.** It said "His game does not let an addon read talents". The game keeps talents in a newer way than the addon looked for. Now it reads that, with the three trees and their names.
- The one being guided needs this version, since his addon does the reading.

## 1.32.2

- The big text and the arrows on the screen of the one being guided keep their calm colours. The brighter colours from 1.32.1 are only for the guide's windows.

## 1.32.1

- **One set of colours everywhere.** Gold is a name or a heading. Green is fine, done or a gain. Orange needs attention soon. Red is urgent, missing or a loss. Before, headings and warnings had the same gold, and text had softer shades than the buttons and chips.
- The leftover blue on "you:" lines is gone.
- When the one being guided says yes to a guide, it is also said on his screen, not only in chat.
- Nothing else changes.

## 1.32.0

- **A small quest list for doing things together.** It shows his progress on the quests you both have, next to yours, and it follows along by itself: he loots something and the number changes a moment later.
- **In a dungeon it shows his quests for that dungeon**, and nothing else.
- **Track** on a row in the Quests tab puts one of his own quests on the list, for when you help him with something you do not have.
- Chat says when he finishes a quest on the list, with where to hand it in. Coming out of a dungeon, it says what he still needs from it.
- When you are done and he is not, his numbers turn yellow.
- **"Ready to go in?"** on the Dungeon tab: his gear, bag space and food, before it is too late to fix.
- `/dadmode tracker` switches the list off and on.
- He needs 1.32.0 too for the list to follow along by itself.

## 1.31.1

- Clearer words. The window no longer talks about "whispers", which is how the addon works inside and not something you need to know. When you are not in a party it now says what to do: open the window once while you are in a party with the one you guide.
- Nothing else changes.

## 1.31.0

- **A Talents tab.** His talent trees are drawn like his own talent window: every talent in its row and column, with its rank. Taken ones are bright, the rest dimmed. Each tree shows its points, so you see his build at a glance.
- **Click a talent to point at it.** His screen says which talent to put his point in, with the tree and the row. He spends the point himself.
- It works for every class. His addon reads whatever trees his character has.
- A new switch under My guides: **See my talents and point at one**.
- Both of you need 1.31.0.

## 1.30.0

- **The bottom of the guide bar is a status strip now.** One line says who you guide, his level, his zone and how far away he is. The next says what needs attention: DEAD, bags full, broken gear, no food, unspent talent points, an older DadMode. Or "all good".
- **Worn gear is said before it breaks**: "gear 18%" when his most worn piece is under 25%.
- With nobody to guide, the strip is gone and the bar is shorter. No more empty space.
- **"A new version is out."** When somebody in your party has a newer DadMode than you, yours says so once, with where to update. The one being guided also sees it as the big text on the screen.

## 1.29.0

- **Everything has the game's own look now.** The guide bar, the window to pick people, the role question, the Yes / No box and the follow button got the gold edge, the warm dark background and dark red buttons with gold text that the "How is he doing" window already had.
- Nothing else changes.

## 1.28.0

- **See how he is doing when he is not in your party.** Your addon remembers the people you have guided. Open the window without them in your party and it asks them by whisper. Nothing shows in chat. "Put it on" works this way too. Both of you need 1.28.0.
- The window says when he is **not online**, and when he is online but **does not answer**.
- Only a guide he has already approved gets an answer from outside the party. Anybody else gets nothing, and no Yes / No box appears.
- Arrows, calls and waypoints still need a party.
- The Overview says for each person whether his answers **arrive by whisper**.
- The text for an empty window is right now: it no longer says "Dad needs DadMode 1.5" when you are simply not in a party.
- `/dadmode forget NAME` takes somebody off the list of people you guide.

## 1.27.0

- **Tell the addon what counts for him.** On the Gear tab, above the items in his bags, click the stats that matter for how he plays (Strength, Agility, Spell Power and so on). Items that gain those stats come first, and their chips are bright while the rest is dimmed. It is remembered for each person.
- **Sort the bag list** by slot, by item level, or by his stats.
- **The whole window is rows and boxes now, not pages of text.** Overview is a grid of small boxes. Quests, Missing and Dungeon have one row for each quest, with small coloured boxes for its state. Dungeons open with a button.
- **The top line says who it is about** on every tab: name, class, level and zone.
- The Gear tab starts with what is in his bags, since that is where there is something to do.
- The window has the game's own look: a gold edge, dark red buttons with gold text, and the game's green and red.

## 1.26.0

- **Gear is now shown as facts, with no verdict.** DadMode no longer says an item is BETTER. It only knew the item level, not how he plays. You see what he gains (green) and what he loses (red), and you decide. This goes for the Gear tab, item tooltips and the chat line on drops.
- **The Gear tab has real rows for what is in his bags.** Slot on the left, the item and what it would replace in the middle, a button on the right. The button shows what happened: Put it on, Asked, He sees it, He put it on.
- Every wearable item in his bags is listed, not only the ones with a higher item level.
- The guide bar no longer says "2 better items in his bags".
- **The far-away warning knows about zones.** When a picked person is far away in another zone, there is no sound and no text. The arrow turns grey and says where they are, like "in Orgrimmar". A call still gets through.
- In the same zone, the far-away warning now comes once each time he drifts off. The text no longer comes back every minute.

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
