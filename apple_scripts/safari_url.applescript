tell application "Safari"
    if (count of windows) is 0 then return ""
    set theTab to current tab of front window
    set theURL to URL of theTab
    return theURL
end tell
