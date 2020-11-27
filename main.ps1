# Get Discord credentials, or ask if they aren't there
try {
    $read = Get-Content -Path "./discordCreds.txt" -erroraction 'silentlycontinue'
    $username = $read[0]
    $password = $read[1]
}
catch {
    $username = Read-Host -Prompt "User Name"
    $password = Read-Host -Prompt "Password"
    Set-Content -Path "./discordCreds.txt" -Value "$username`n$password"
}
$headless = Read-Host -Prompt "Headless? [y/n]"
$keyWord = Read-Host -Prompt "Messaging keyword"
$fileName = Read-Host -Prompt "IP File Path"
$ipList = Get-Content -Path $fileName
$ips = $ipList.length-1

if($headless -eq "n") {
    $Driver = Start-SeChrome -Arguments @('start-maximized') -Quiet
}
else {
    $Driver = Start-SeChrome -Arguments @('headless', 'start-maximized') -Quiet
}
Enter-SeUrl "https://www.discord.com/login" -Driver $Driver

# Got this from an issue, lets you hover over an element
function Set-SeMousePosition {
    [CmdletBinding()]
    param ($Driver, $Element )
    $Action = [OpenQA.Selenium.Interactions.Actions]::new($Driver)
    $Action.MoveToElement($Element).Perform()
}

# This gets a list of all message after the 'new' bar on discord
function getNewMessages($messagesList) {
    $coords = (Find-SeElement -Driver $Driver -classname "divider-3_HH5L")[-1].Location.Y # The Y-coordinate of the 'new' bar
    $newMessages = @()
    for($i = 0; $i -lt $messagesList.Length; $i += 1) {
        if($messagesList[$i].Location.Y -gt $coords) {
            $newMessages += ($messagesList[$i])
        }
    }
    return $newMessages
}


$Element = Find-SeElement -Driver $Driver -ClassName "inputDefault-_djjkz" # Username/email and password login inputs
$UN = $Element[0]
Send-SeKeys -Element $UN -Keys $username
$PW = $Element[1]
Send-SeKeys -Element $PW -Keys $password
$login = Find-SeElement -Driver $Driver -ClassName "marginBottom8-AtZOdT" # Login button
Invoke-SeClick -Element $login[1]
# This gets the amount of servers the user is in, to know which of the buttons are users or not.
$newMessage = Find-SeElement -driver $Driver -classname "wrapper-1BJsBx" # The person/server menu buttons on the top left
$menus = $newMessage.length
for($i = 0; $i -lt $newMessage.length; $i++) {
    $attrib = $newMessage[$i]
    try {
        if($attrib.GetAttribute("href").substring(10, 3) -eq "@me") {
            $menus -= 1
        }
    }
    catch {
        continue
    }
}
Write-Host "$menus servers being ignored."
Write-Host "Ready."
$menus += 1
while($true) {
    $newMessage = Find-SeElement -driver $Driver -classname "wrapper-1BJsBx" # The person/server menu buttons on the top left
    if($newMessage.Length -le ($menus)) {
        Start-Sleep 2
        continue
    }
    $attribute = $newMessage[1].GetAttribute("data-list-item-id") # This is the 'guildsnav___USERID' part of the menu buttons
    $id = $attribute.Substring(12, 18)
    # This is the little red icon in the bottom right of each menu button
    $amount = (Find-SeElement -driver $driver -classname "numberBadge-2s8kKX").GetAttribute("innerText")
    $sent = Get-Content -path "./sentFile.txt" -erroraction "silentlycontinue"
    $notSent = Get-Content -path "./notSentFile.txt" -erroraction "silentlycontinue"
    try {
        # This checks if $id has already been sent an IP, or if the script has already checked that chat for the current messages
        if($sent -icontains $id -or ($notSent -icontains $id+":"+$amount)) {
            continue
        }
    }
    catch {
        continue
    }
    $user = $newMessage[1].GetAttribute("aria-label") # This gets the users name
    $addS = ''
    if($amount -gt 1) { # Gets correct usage for 'message' or 'messages'
        $addS = 's'
    }
    Write-Host "Checking new message$addS from $user"
    Enter-SeUrl "https://discord.com/channels/@me/$id" -Driver $Driver
    $messagesList = Find-SeElement -Driver $Driver -classname "contents-2mQqc9" # These are all the messages in the chat
    $send = $false
    $result = getNewMessages $messagesList
    $keyWords = 0
    for($i = 0; $i -lt $result.length; $i++) {
        $message = $result[$i]
        if((Find-SeElement -driver $message -tagname "div")[0].GetAttribute("innerText") -eq $keyWord) { # Checks each messages text to see if it matches $keyWord
            $send = $true
            $keyWords += 1
        }
        elseif ($ipList -icontains $keyWord) {
            $keyWords += 1
        }
    }
    $chatboxes = Find-SeElement -Driver $Driver -classname "slateTextArea-1Mkdgw" # The messaging input box
    if($send) {
        $IP = $ipList[$ips]
        Write-Host "Sent IP $IP to $user"
        Add-Content -Path "./sentFile.txt" -Value $id # Send $id to file so the script knows to ignore new messages from that user
        Send-SeKeys -Element $chatboxes[0] -Keys "$IP`n" # Send the IP
        $ips -= 1
        Set-Content -Path $fileName -Value $ipList[0]
        for($i = 1; $i -le $ips; $i += 1) {
            Add-Content -Path $fileName -Value $ipList[$i]
        }
        $ipList = Get-Content -Path $fileName
    }
    else {
        $length = $result.Length
        # Send $id, along with the amount of new messages, so the script knows to ignore until another message comes in
        Add-Content -Path "./notSentFile.txt" -Value "${id}:$length"
    }
    # Set mouse to hover over message input box.  Prevents bugs from happening when mouse is already where it needs to be later
    Set-SeMousePosition -Driver $Driver -Element $chatboxes[0]
    if($result.Length -gt $keyWords -or (!$send -and ($result.Length -eq 1))) {
        $clickee = $result[0]
        Set-SeMousePosition -Driver $Driver -Element $clickee # Set mouse to hover over the earliest new message
        $button = (Find-SeElement -Driver $Driver -classname "button-1ZiXG9")[2] # The three dots that show up on hover
        Send-SeClick -Element $button
        $clickee = (Find-SeElement -Driver $Driver -classname "label-22pbtT")[2] # The 'Mark Unread' button in the three dots menu
        Send-SeClick -Element $clickee
    }
    $send = $false
    Enter-SeUrl "https://discord.com/channels/@me" -Driver $Driver
}