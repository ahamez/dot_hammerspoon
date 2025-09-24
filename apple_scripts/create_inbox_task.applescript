set theTaskName to "%s"
set theNote to "%s"
tell application "OmniFocus"
    tell default document
        make new inbox task with properties {name:theTaskName, note:theNote}
    end tell
end tell
