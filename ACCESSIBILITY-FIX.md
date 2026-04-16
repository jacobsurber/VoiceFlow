# Fix Whisp Accessibility Permission

## Problem

Smart Paste says accessibility is needed, but it appears enabled in System Settings.

The same root cause can also affect Microphone and Input Monitoring after a rebuild.

## Why This Happens

When Whisp is rebuilt with ad-hoc signing, the code signature changes. macOS treats it as a "new" app and can block Accessibility, Input Monitoring, or re-prompt for Microphone, even though the old entry still shows in System Settings.

The durable fix is to create a stable local signing identity once:

```bash
make setup-local-signing
make install
```

After that, macOS should keep the same privacy permissions across rebuilds.

## Solution: Remove and Re-Add

### Step 1: Remove Old Entry

1. Open **System Settings** → **Privacy & Security** → **Accessibility**
2. Find **Whisp** in the list (you might see multiple entries or an old one with a different icon)
3. Click the **-** (minus) button to remove it
4. If you see multiple Whisp entries, remove **all** of them

### Step 2: Quit Whisp

```bash
pkill -x Whisp
```

### Step 3: Re-Add Fresh Entry

1. Launch Whisp: `open /Applications/Whisp.app`
2. Try to record something (press your hotkey)
3. Whisp will show a dialog explaining accessibility permission
4. Click **"Grant Permission"**
5. System Settings will open to Accessibility
6. Click the **+** (plus) button
7. Navigate to **Applications** → select **Whisp.app**
8. Make sure the toggle is **ON**

### Step 4: Test Smart Paste

1. Open any text editor (Notes, TextEdit, etc.)
2. Click in the text field
3. Press your recording hotkey (default: Left Control - hold)
4. Speak something
5. Release the hotkey
6. Wait for transcription
7. **Text should auto-paste** into the editor

## Alternative: Disable Smart Paste

If you prefer manual pasting:

1. Open Whisp Settings
2. Disable "Smart Paste"
3. After transcription, manually press ⌘V to paste

## Still Not Working?

If the above doesn't work, the app likely needs a stable signature. Run:

```bash
cd /path/to/Whisp
make setup-local-signing
make install
```

Then repeat the steps above to remove and re-add the affected permission.
