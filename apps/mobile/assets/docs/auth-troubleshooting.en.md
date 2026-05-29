# Claude Authentication Troubleshooting

CC Pocket uses the Claude Code login state stored on your Bridge machine.
If authentication fails, sign in to Claude Code again on that machine.

## Subscription vs API Key

Claude Code can use your Claude.ai Pro, Max, Team, or Enterprise subscription
login. It can also use Console API credentials. If `ANTHROPIC_API_KEY` or
`ANTHROPIC_AUTH_TOKEN` is set in the Bridge process environment, Claude Code
will use that credential before subscription login, which can result in API
billing. To use your subscription allocation, keep those environment variables
unset on the Bridge machine and verify the active account with `/status` in
Claude Code.

## If You Are Not Near Your Bridge Machine

With CC Pocket, your Bridge machine may be a Mac mini or another Mac running at home.
Even in that case, you can log back into Claude Code remotely from your phone.

1. Connect to the Bridge machine from a terminal app
   - Moshi, Termius, Blink, or any SSH client works
2. Run `claude`
3. Run `/login` inside Claude Code
4. Open the displayed URL on your phone or PC
5. Complete sign-in in the browser
6. Paste the result back into the terminal if prompted

CC Pocket will use the updated login on the next request.

## If You Are Near Your Bridge Machine

1. Run `claude` on the Bridge machine
2. Run `/login`
3. Complete the browser sign-in flow

## Shell Alternative

If you prefer, you can also run:

```bash
claude auth login
```

## When This Happens

- Your Claude login expired
- Claude Code was updated and the old login became invalid
- Anthropic revoked the saved token
