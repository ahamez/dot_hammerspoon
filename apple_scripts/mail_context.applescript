on replaceText(find, replace, subjectText)
    repeat while subjectText contains find
        set AppleScript's text item delimiters to find
        set subjectText to text items of subjectText
        set AppleScript's text item delimiters to replace
        set subjectText to subjectText as string
    end repeat
    set AppleScript's text item delimiters to ""
    return subjectText
end replaceText

set delim to ASCII character 31 -- unit separator to avoid collisions
tell application "Mail"
    try
        set theMsg to missing value
        -- First try the generic selection API
        try
            set sel to selection
            if sel is not {} then set theMsg to item 1 of sel
        end try
        -- If no message yet, try the front message viewer's selected messages
        if theMsg is missing value then
            try
                set selMsgs to selected messages of front message viewer
                if selMsgs is not {} then set theMsg to item 1 of selMsgs
            end try
        end if
        if theMsg is missing value then return ""
        set theID to message id of theMsg
        if theID is missing value then return ""
        set theSubject to subject of theMsg
        set theSender to sender of theMsg
        set theDate to date received of theMsg
        set idText to theID as text
        set idText to my replaceText("\n", "", idText)
        set idText to my replaceText("\r", "", idText)
        -- Ensure angle brackets are present before encoding
        if idText is not "" and (text 1 of idText) is not "<" then set idText to "<" & idText & ">"
        -- Percent-encode only angle brackets for Mail message URLs
        set idEnc to my replaceText("<", "%3C", idText)
        set idEnc to my replaceText(">", "%3E", idEnc)
        set linkText to "message://" & idEnc
        return theSubject & delim & theSender & delim & (theDate as string) & delim & linkText
    on error
        return ""
    end try
end tell
