# Teams Meeting Controls

Language for controlling Microsoft Teams meetings from Stream Deck.

## Language

**Reaction wave**:
A bounded sequence of attempts to send the same meeting reaction while its Stream Deck key is held. It ends when the key is released or the session limit is reached; attempts do not imply confirmed delivery to other participants.
_Avoid_: Unlimited repeat, guaranteed delivery

**Reaction attempt**:
An attempt to send one meeting reaction. Acceptance of an attempt by the local interface is not confirmation that another participant received it.
_Avoid_: Delivered reaction, received reaction

**Confirmed reaction delivery**:
A reaction observed by another participant or a second device in the meeting.
_Avoid_: Accepted attempt, local success
