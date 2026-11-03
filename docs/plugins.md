# plugins

how to write a plugin for exteria. a plugin is one lua 5.4 file that reads the messages going through the chat and may hide them or change their text.

plugins are not a way to call the api, touch files or the network. the host gives a script the text of a message and takes one answer back, nothing else.

## the file

a script runs once when it is loaded and returns a table:

```lua
return {
  name = "no-spam",
  permissions = { "messages.read", "messages.modify" },
  on_message = function(m)
    if m.text:find("spam", 1, true) then return false end
  end,
}
```

- `name`: 1 to 64 printable characters, no control characters; shown in the list
- `permissions`: a list of strings, may be empty, at most 8; an unknown one refuses the plugin
- hooks: `on_message`, `on_send`, `on_event`; at least one, and each must be a function
- other fields are ignored

the script runs in a sandbox with a budget, see the limits. whatever it does at the top level counts against the same budget as a hook call.

## permissions

- `messages.read`: the hook sees the `text` field. without it `m.text` is nil
- `messages.modify`: the hook may hide a message or replace its text

an answer other than nil without `messages.modify` fails the call with the reason `messages.modify is not granted`, and the message is left alone.

## hooks

### on_message(m)

called for a message of someone else before it is drawn, in the chat and in the peek at a chat.

- `m.id`: the id of the message
- `m.chat`: the peer id of the chat
- `m.sender`: the id of the sender
- `m.outgoing`: always false, since your own messages are not passed
- `m.text`: the text, with `messages.read`

return nil to leave the message, false to hide it, a string to show another text. `true`, a number or a table is a failure.

a replacement must be valid utf-8, not empty, no longer than 16 KiB. a string equal to the text is not an edit. the original text is kept by the app, a replaced one only changes what is shown.

the answer for a message is kept, and asked for again only when a plugin is switched on or off or a file changes. the hook can still run more than once for the same message, so keep it free of side effects and of state that changes the answer.

messages of the service kind (a person joined, a pin) and messages that are not sent yet are not passed.

### on_send(m)

called for a text the person is about to send, before it goes out.

- `m.chat`: the peer id of the chat
- `m.reply_to`: the id of the message it answers, 0 for none
- `m.text`: the text, with `messages.read`

nil sends it as it is, false stops it, a string sends that text instead. when it is stopped the person sees a notice that the words went nowhere. the input field is already cleared by then.

a replaced text goes out without its formatting: the runs of bold, links and the like would point into the old words.

the hooks of several plugins run one after another, in the order of the file names, and each sees the text the one before left.

### on_event(name)

`name` is `start` (the app launched and the plugin is loaded), `stop` (the app ends), `pause` (it goes to the background) or `resume` (it comes back). the answer is ignored. a plugin turned on while the app runs does not get `start`, it gets the events that follow.

## what the sandbox has

- base functions: `assert error ipairs next pairs pcall select tonumber tostring type xpcall setmetatable getmetatable rawget rawset rawequal rawlen`
- the libraries `string`, `table`, `math` and `utf8`, without `string.dump`
- `log(text)`: writes a line to the device log as `exteria: plugin <name>: <line>`

there is no `io`, `os`, `load`, `require`, `print`, `collectgarbage` or `debug`, and a script loads as text only, so no bytecode runs.

`log` clips a line to 200 characters and takes 16 lines per call; the 17th raises an error.

## limits

- script: 64 KiB
- text passed to a hook or returned from it: 16 KiB. a longer text skips the plugins, since a plugin cannot be shown half of a message
- 200000 vm instructions for the load and for each hook call, about 10 ms on an iphone 4. `pcall` does not save a script from this, the budget error comes back at the next instruction
- 2 MiB of memory for the whole state
- 64 plugins listed in the folder

## the life of a plugin

put the file in `Documents/Plugins`. file sharing is on, so it can be copied from a computer, or imported in settings, plugins, "Import plugin". import copies the file, replaces one of the same name, and never turns it on.

the settings page lists every `.lua` file (a lowercase extension) with its name, hooks and permissions, or the reason the host refused it.

- a plugin runs only after the person turns it on, and sees what it asks for before that
- the switch is tied to the sha-256 of the file. a changed file is off until it is turned on again, because it may now ask for more
- three failed calls in a row switch the plugin off, and the page shows the last failure. a call that works resets the count
- a plugin is deleted by deleting its file

a refusal is one of: not a valid script (syntax error, no table, no name, no hook, bad permissions), an unknown permission, too large or too many permissions, ran too long or used too much memory while loading.

hooks run on the main thread only. a call from another thread passes the message through and writes why to the log.

## try it

write the plugin, copy it to `Documents/Plugins`, open settings, plugins and turn it on. watch the log of the device for `exteria: plugin`; `log` is the only debugger there is.

two more examples:

```lua
-- makes every text sent in lowercase
return {
  name = "quiet",
  permissions = { "messages.read", "messages.modify" },
  on_send = function(m)
    return m.text:lower()
  end,
}
```

```lua
-- writes the app events to the log, needs no permission
return {
  name = "event-log",
  permissions = {},
  on_event = function(name)
    log("event " .. name)
  end,
}
```

a plugin keeps no state between launches: the state of the script is gone when the app ends.

## the host

the host is `core/plugins`, plain c with lua 5.4 and no uikit, and its tests are `tests/core/test_plugin.c`:

```bash
PATH=/usr/local/bin:/usr/bin:/bin make -C tests CC=gcc test
```

- `exteria_plugin_load` runs the script and reads the table; its status says why it refused (`EXTERIA_E_MALFORMED`, `EXTERIA_E_UNSUPPORTED`, `EXTERIA_E_LIMIT`, `EXTERIA_E_TIMEOUT`, `EXTERIA_E_NOMEM`)
- `exteria_plugin_on_message`, `exteria_plugin_on_send` and `exteria_plugin_on_event` call a hook; on any failure the action is pass and the caller keeps the original
- `app/platform/exteria_plugins.m` is the folder, the switches, the digests and the hooks into the chat (`ExteriaPluginsHidesMessage`, `ExteriaPluginsStopsSend`, `ExteriaPluginsEvent`)
- `app/features/settings/exteria_plugins_controller.m` is the page

a new permission or hook is a change in the host, with a test for the answer that is refused and for the one that is allowed, and a line in the strings for the page (`plugins.perm.*`, `plugins.hook.*`).
