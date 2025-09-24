tell application "%s"
    if (count of windows) is 0 then return ""
    set theTab to active tab of front window
    set theURL to URL of theTab
    return theURL
end tell
