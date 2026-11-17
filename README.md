# tg-bot-test

A Telegram bot in pure bash + curl, built to run inside the AGT app on an
Android phone (no python, no node). It long-polls the Telegram Bot API and
answers:

- /start: greeting
- /ping: pong with the phone's clock
- /status: uptime and free space on the phone
- any other text: echoed back

The bot token is never stored in this repo. At runtime the bot reads it
from token.txt next to bot.sh, or from bot-token.txt in the app home,
injected onto the phone by a signed job.
