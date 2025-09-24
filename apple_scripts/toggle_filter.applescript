tell application "OmniFocus"
    if not (exists document 1) then return
    tell document 1
        if not (exists document window 1) then return
        tell document window 1
            set theContent to content
            if theContent is missing value then return
            set currentFilter to selected task state filter identifier of theContent
            if currentFilter is "available" then
                set selected task state filter identifier of theContent to "incomplete"
            else
                set selected task state filter identifier of theContent to "available"
            end if
        end tell
    end tell
end tell
