# :'(
param
(
    [Parameter(Mandatory = $true)]
    [securestring]
    $SlackToken,

    [Parameter()]
    [string]
    $MapPath = './configuration/slack_teams_map.yml'
)

if (-not (Get-Module -ListAvailable -Name powershell-yaml)) {
    Install-Module -Name powershell-yaml -Repository PSGallery -AllowClobber -Force
}

if (-not (Get-Module -ListAvailable -Name MiniGraph)) {
    Install-Module -Name MiniGraph -Repository PSGallery -AllowClobber -Force
}

MiniGraph\Connect-GraphAzure -ErrorAction Stop

function ConvertFrom-UnixTime {
    param
    (
        [string]
        $UnixTime
    )

    $dateTime = [datetime]::new(1970, 1, 1, 0, 0, 0, 0, [DateTimeKind]::Utc)
    $dateTime.AddSeconds( $UnixTime ).ToLocalTime()
}

$mappings = Get-Content -Path $MapPath -Raw | ConvertFrom-Yaml

$uris = @{
    ListPrivateChannels          = 'https://slack.com/api/conversations.list?types=private_channel&exclude_archived=true'
    ListPublicChannels           = 'https://slack.com/api/conversations.list?types=public_channel&exclude_archived=true'
    ListUsers                    = 'https://slack.com/api/users.list'
    ListEntraUser                = 'users?$select=id,userPrincipalName,displayName'
    History                      = 'https://slack.com/api/conversations.history'
    TeamsListUri                 = 'teams?$select=id,displayName,internalId'
    TeamsMembersUri              = 'teams/{0}/members'
    TeamsChannelListUri          = "teams/{0}/allChannels"
    TeamsChannelUri              = "teams/{0}/channels"
    TeamsChannelArchiveUri       = 'teams/{0}/channels/{1}/archive'
    TeamsChannelUnarchiveUri     = 'teams/{0}/channels/{1}/unarchive'
    TeamsDriveRefresh            = "teams/{0}/channels/{1}/filesFolder"
    TeamsMessageUri              = 'teams/{0}/channels/{1}/messages'
    TeamChannelMigrationComplete = 'teams/{0}/channels/{1}/completeMigration'
    TeamMigrationComplete        = 'teams/{0}/completeMigration'
    TeamFilter                   = "teams?`$filter=displayName eq '{0}'"
    TeamChannelFilter            = "teams/{0}/channels?`$filter=displayName eq '{1}'"
}

$PSDefaultParameterValues = @{
    'Invoke-RestMethod:Authentication' = 'Bearer'
    'Invoke-RestMethod:Token'          = $SlackToken
}

# Get all available channels
[System.Collections.ArrayList] $channels = [System.Collections.ArrayList]::new()
$channelsRequest = Invoke-RestMethod -Uri $uris['ListPublicChannels'] -Method Get
if (-not $channelsRequest.ok) {
    "Unable to list public channels. Error: $($channelsRequest.error)."
    exit 1
}
$channels.AddRange($channelsRequest.channels)

$privateChannelsRequest = Invoke-RestMethod -Uri $uris['ListPrivateChannels'] -Method Get
if (-not $privateChannelsRequest.ok) {
    "Unable to list private channels. Error: $($privateChannelsRequest.error)."
    exit 1
}
$channels.AddRange($privateChannelsRequest.channels)

# Get list of Slack users and map to Entra users
$slackUsers = (Invoke-RestMethod -Uri $uris['ListUsers'] -Method Get ).members | Where-Object { -not $_.is_bot } | Group-Object { $_.id } -AsHashTable -AsString
$entraUsers = Invoke-GraphRequest -Query $uris['ListEntraUsers'] | Group-Object { $_.userPrincipalName } -AsHashTable -AsString

# Get all Teams
$teams = @{}

foreach ($team in (Invoke-GraphRequest -Query $uris['TeamsListUri'] -ErrorAction Stop)) {
    $teams[$team.id] = @{
        Team     = $team
        Channels = [System.Collections.ArrayList]::new()
    }

    $teamsChannels = Invoke-GraphRequest -Query ($uris['TeamsChannelListUri'] -f $team.id)
    Start-Sleep -Milliseconds 125
    if ($teamsChannels) {
        $teams[$team.id].Channels.AddRange([array]$teamsChannels)
    }
}

# Create all teams
foreach ($team in $mappings.Values.TeamName | Sort-Object -Unique) {
    $teamResponse = Invoke-GraphRequest ($uris['TeamFilter'] -f $team) -ErrorAction SilentlyContinue
    if (-not $teamResponse) {
        $teamResponse = Invoke-GraphRequest -Method Post -Query teams -Body @{
            "@microsoft.graph.teamCreationMode" = "migration"
            "template@odata.bind"               = "https://graph.microsoft.com/v1.0/teamsTemplates('standard')"
            "displayName"                       = $team
            "description"                       = "Team under migration: $team"
            "createdDateTime"                   = "2022-01-01T08:00:00.000Z"
        }
        Start-Sleep -Seconds 5 # Really.
    }

    $start = Get-Date
    while ($null -eq $teamResponse -and ((Get-Date) - $start) -lt '00:05:00') {
        $teamResponse = Invoke-GraphRequest ($uris['TeamFilter'] -f $team)
        Start-Sleep -Milliseconds 250
        if (((Get-Date) - $start) -ge '00:05:00') {
            throw "Unable to create team '$team' within 5 minutes."
        }
    }

    # Create all channels
    foreach ($channel in $mappings.GetEnumerator() | Where { $_.Value.TeamName -eq $teamResponse.displayName -and $_.Value.ChannelType -eq 'standard' }) {
        $slackChannel = $channels | Where-Object name -eq $channel.Key
        $teamsChannelBody = @{
            "@microsoft.graph.channelCreationMode" = "migration"
            membershipType                         = $channel.Value.ChannelType
            displayName                            = $channel.Value.ChannelName
            description                            = if ($slackChannel.purpose.value) { $slackChannel.purpose.value } else { "Migrated from Slack channel $($channel.Key)" }
            "createdDateTime"                      = '{0:yyyy-MM-ddTHH:mm:ss.fffZ}' -f (ConvertFrom-UnixTime $slackChannel.created)
        }
            
        # Create channel
        $channelResponse = Invoke-GraphRequest -Query ($uris['TeamChannelFilter'] -f $teamResponse.id, $channel.Value.ChannelName) -ErrorAction SilentlyContinue
        if (-not $channelResponse) {
            try {
                "Creating new Teams channel '$($channel.Value.ChannelName)'."
                $channelResponse = Invoke-GraphRequest -Query ($uris['TeamsChannelUri'] -f $teamResponse.id) -Body $teamsChannelBody -Method Post -ErrorAction Stop
            }
            catch {
                "Unable to create new Teams channel '$($channel.Value.ChannelName)', $($teamsChannelBody | ConvertTo-Json -Depth 5), $($_.Exception.Message)"
            }
        }

        $historyResponse = Invoke-RestMethod -Uri $uris['History'] -Method Post -Body @{
            channel = $slackChannel.id
        }
        if (-not $historyResponse.ok) {
            "Unable to get history for channel '$($slackChannel.name)'. Error: '$($historyResponse.error)'."
            continue
        }

        $messages = [System.Collections.ArrayList]::new()
        $messages.AddRange(($historyResponse.messages | Where-Object { $_.type -eq "message" -and -not $_.subtype }))

        while ($historyResponse.has_more) {
            $historyResponse = Invoke-RestMethod -Uri $uris['History'] -Method Post -Body @{
                channel = $slackChannel.id
                latest  = $historyResponse.messages[-1].ts
            }
            $messagesToAdd = [array]($historyResponse.messages | Where-Object { $_.type -eq "message" -and -not $_.subtype })
            if ($messagesToAdd) { $messages.AddRange($messagesToAdd) }
            Start-Sleep -Milliseconds 50
        }
        
        $channelPath = Join-Path $pwd -ChildPath "MessageMigration/$($teamResponse.displayName)/$($channelResponse.displayName)"
        if (-not (Test-Path $channelPath)) {
            $null = New-Item -Path $channelPath -ItemType Directory -Force
        }

        foreach ($message in $messages) {
            if (-not $message.text -and $message.files) {
                Write-Warning "Empty message, skipping. Probably file content only."
                continue
            }
            # profile.email
            $messageText = $message.text
            $messageTime = '{0:yyyyMMdd_HHmmss_fff}' -f (ConvertFrom-UnixTime -UnixTime $message.ts)

            $slackUser = $slackUsers[$message.user]
            if ($slackUser.deleted) {
                $slackUser = @{
                    real_name = $slackUser.real_name
                    profile   = @{
                        email = 'David.DasNeves@shiftavenue.com'
                    }
                }
                $messageText = "Originally sent by $($slackUser.real_name):`r`n`r`n{0}" -f $messageText
            }

            if (-not $slackUser -or -not $slackUser.profile.email) {
                Write-Warning "Cannot post message, unknown/unmapped slack user '$($message.user)' or empty mail '$($slackUser.profile.email)'"
                $messageText | Set-Content -Path (Join-Path $channelPath "$($messageTime).txt")
                continue
            }

            $entraUser = $entraUsers[$slackUser.profile.email]
            if (-not $entraUser) {
                Write-Warning "Cannot post message, unknown/unmapped slack user '$($slackUser.id)' ($($slackUser.real_name)) or empty mail '$($slackUser.profile.email)'"
                $messageText | Set-Content -Path (Join-Path $channelPath "$($messageTime).txt")
                continue
            }

            $newMessage = @{
                createdDateTime = '{0:yyyy-MM-ddTHH:mm:ss.fffZ}' -f (ConvertFrom-UnixTime -UnixTime $message.ts)
                body            = @{
                    contentType = 'html'
                }
                mentions        = [System.Collections.generic.list[hashtable]]::new()
                from            = @{
                    user = @{
                        id               = $entraUser.id
                        displayName      = $entraUser.displayName
                        userIdentityType = 'aadUser'
                    }
                }
            }

            # Replace mentions and channel-mention
            $mentionCounter = 0
            if ($messageText.Contains('<!here>')) {
                $messageText = $messageText.Replace('<!here>', "<at id=`"$mentionCounter`">$($channelResponse.displayName)</at>")
                $newMessage.mentions.Add(@{
                        id          = $mentionCounter
                        mentionText = $channelResponse.displayName
                        mentioned   = @{
                            conversation = @{
                                id                       = $channelResponse.id
                                displayName              = $channelResponse.displayName
                                conversationIdentityType = "channel"
                            }
                        }
                    })
                $mentionCounter++
            }

            $userMentions = @{}
            foreach ($mention in ($messageText | Select-String -Pattern "(<@([A-Z0-9]+)>)" -AllMatches).Matches) {
                $slackUser = $slackUsers[$mention.Groups[2].Value].profile.email
                if (-not $slackUser) {
                    $messageText = $messageText.Replace($mention.Groups[1].Value, 'UNKNOWN_USER')
                    continue
                }
                $entraUser = $entraUsers[$slackUser]
                if (-not $entraUser) {
                    $messageText = $messageText.Replace($mention.Groups[1].Value, 'UNKNOWN_USER')
                    continue
                }

                $userMentions[$entraUser.displayName] = @{
                    replace = $mention.Groups[1].Value
                    mention = @{
                        mentionText = $entraUser.displayName
                        mentioned   = @{
                            user = @{
                                id               = $channelResponse.id
                                displayName      = $entraUser.displayName
                                userIdentityType = "aadUser"
                            }
                        }
                    }
                }
            }

            foreach ($mention in $userMentions.GetEnumerator()) {
                $messageText = $messageText.Replace($mention.Value.replace, "<at id=`"$mentionCounter`">$($mention.Key)</at>")
                $mention.Value.mention.id = $mentionCounter
                $newMessage.mentions.Add($mention.Value.mention)
                $mentionCounter++
            }

            $newMessage.body.content = $messageText

            if ($newMessage.mentions.Count -eq 0) {
                $newMessage.Remove('mentions')
            }

            try {
                $null = Invoke-GraphRequest -Query ($uris['TeamsMessageUri'] -f $teamResponse.id, $channelResponse.id) -Method Post -Body $newMessage -ErrorAction Stop
            }
            catch {
                if ($_.Exception.Response.StatusCode -eq 'Conflict' -or ($_.ErrorDetails | ConvertFrom-Json).error.innerError.message -eq 'MessageWritesBlocked-Thread is not marked for import') {
                    Write-Verbose "Message exists or channel migration complete"
                }
                else {
                    Write-Warning "Unable to post Slack message with timestamp, saving it $($message.ts). $($_.Exception.Message)"
                    $_.Exception | Format-List -Property * -Force | Out-String | Set-Content -Path (Join-Path $channelPath "$($messageTime)_error.txt")
                    $messageText | Set-Content -Path (Join-Path $channelPath "$($messageTime).txt")
                }
            }
        }

        # Skip General channel - it is undocumented, but closing the migration for this channel finalizes the team :)
        if ($channelResponse.displayName -eq 'General') {
            continue
        }

        try {
            Invoke-GraphRequest -Query ($uris['TeamChannelMigrationComplete'] -f $teamResponse.id, $channelResponse.id) -Method Post -ErrorAction Stop
        }
        catch {
            if (($_.ErrorDetails | ConvertFrom-Json).Error.message -ne 'Channel has already been finalized.') { throw }
        }
    }

    $general = Invoke-GraphRequest -Query "teams/$($teamResponse.id)/channels?`$filter=displayName eq 'General'"
    try {
        Invoke-GraphRequest -Query ($uris['TeamChannelMigrationComplete'] -f $teamResponse.id, $general.id) -Method Post -ErrorAction Stop
    }
    catch {
        if (($_.ErrorDetails | ConvertFrom-Json).Error.message -ne 'Channel has already been finalized.') { throw }
    }

    try {
        Invoke-GraphRequest -Query ($uris['TeamMigrationComplete'] -f $teamResponse.id) -Method Post -ErrorAction Stop
    }
    catch {
        if (($_.ErrorDetails | ConvertFrom-Json).Error.message -notlike '*already been finalized.') { throw }
    }
    
    # Create private channels *after* migration
    $teamResponse = Invoke-GraphRequest ($uris['TeamFilter'] -f $team) -ErrorAction SilentlyContinue
    $null = Invoke-GraphRequest -Query ($uris['TeamsMembersUri'] -f $teamResponse.id) -Method Post -Body @{
        "@odata.type"     = "#microsoft.graph.aadUserConversationMember"
        "user@odata.bind" = if ($env:COMPUTERNAME -eq 'S1-0666-W') { "https://graph.microsoft.com/v1.0/users('admin@M365x00803246.onmicrosoft.com')" } else { "https://graph.microsoft.com/v1.0/users('Benedikt.Gunzelmann@shiftavenue.com')" }
        "roles"           = @("owner")
    } -ErrorAction SilentlyContinue
    foreach ($channel in $mappings.GetEnumerator() | Where { $_.Value.TeamName -eq $teamResponse.displayName }) {
        $slackChannel = $channels | Where-Object name -eq $channel.Key
        $teamsChannelBody = @{
            membershipType = $channel.Value.ChannelType
            displayName    = $channel.Value.ChannelName
            description    = if ($slackChannel.purpose.value) { $slackChannel.purpose.value } else { "Migrated from Slack channel $($channel.Key)" }
        }
        
        if ($channel.Value.ChannelType -eq 'private') {
            if (-not $channel.Value.PrimaryOwner) {
                Write-Warning "Unable to create private channel without owner."
                continue
            }
        
            $owner = $entraUsers[$channel.Value.PrimaryOwner]
        
            if (-not $owner) {
                Write-Warning "Unable to create private channel without owner, $($channel.Value.PrimaryOwner) was not found."
                continue
            }
            $teamsChannelBody.members = @(
                @{
                    '@odata.type'     = '#microsoft.graph.aadUserConversationMember'
                    'user@odata.bind' = "https://graph.microsoft.com/v1.0/users/$($owner.id)"
                    roles             = @('owner')
                }
            )

            $null = Invoke-GraphRequest -Query ($uris['TeamsMembersUri'] -f $teamResponse.id) -Method Post -Body @{
                "@odata.type"     = "#microsoft.graph.aadUserConversationMember"
                "user@odata.bind" = "https://graph.microsoft.com/v1.0/users/$($owner.id)"
            } -ErrorAction SilentlyContinue
        }
    
        # Create channel
        $channelResponse = Invoke-GraphRequest -Query ($uris['TeamChannelFilter'] -f $teamResponse.id, $channel.Value.ChannelName) -ErrorAction SilentlyContinue
        if (-not $channelResponse) {
            try {
                "Creating new Teams channel '$($channel.Value.ChannelName)'."
                $channelResponse = Invoke-GraphRequest -Query ($uris['TeamsChannelUri'] -f $teamResponse.id) -Body $teamsChannelBody -Method Post -ErrorAction Stop
            }
            catch {
                "Unable to create new Teams channel '$($channel.Value.ChannelName)', $($teamsChannelBody | ConvertTo-Json -Depth 5), $($_.Exception.Message)"
            }
        }

        $null = Invoke-GraphRequest -Query ($uris['TeamsDriveRefresh'] -f $teamResponse.id, $channelResponse.id) -ErrorAction SilentlyContinue
    }

    foreach ($channel in $mappings.GetEnumerator() | Where { $_.Value.TeamName -eq $teamResponse.displayName }) {
        $slackChannel = $channels | Where-Object name -eq $channel.Key
        $teamsChannelBody = @{
            membershipType = $channel.Value.ChannelType
            displayName    = $channel.Value.ChannelName
            description    = if ($slackChannel.purpose.value) { $slackChannel.purpose.value } else { "Migrated from Slack channel $($channel.Key)" }
        }
        
        if ($channel.Value.ChannelType -eq 'private') {
            if (-not $channel.Value.PrimaryOwner) {
                Write-Warning "Unable to create private channel without owner."
                continue
            }
        
            $owner = $entraUsers[$channel.Value.PrimaryOwner]
        
            if (-not $owner) {
                Write-Warning "Unable to create private channel without owner, $($channel.Value.PrimaryOwner) was not found."
                continue
            }
            $teamsChannelBody.members = @(
                @{
                    '@odata.type'     = '#microsoft.graph.aadUserConversationMember'
                    'user@odata.bind' = "https://graph.microsoft.com/v1.0/users/$($owner.id)"
                    roles             = @('owner')
                }
            )

            $null = Invoke-GraphRequest -Query ($uris['TeamsMembersUri'] -f $teamResponse.id) -Method Post -Body @{
                "@odata.type"     = "#microsoft.graph.aadUserConversationMember"
                "user@odata.bind" = "https://graph.microsoft.com/v1.0/users/$($owner.id)"
            } -ErrorAction SilentlyContinue
        }
    
        # Create channel
        $channelResponse = Invoke-GraphRequest -Query ($uris['TeamChannelFilter'] -f $teamResponse.id, $channel.Value.ChannelName) -ErrorAction SilentlyContinue
        if (-not $channelResponse) {
            try {
                "Creating new Teams channel '$($channel.Value.ChannelName)'."
                $channelResponse = Invoke-GraphRequest -Query ($uris['TeamsChannelUri'] -f $teamResponse.id) -Body $teamsChannelBody -Method Post -ErrorAction Stop
            }
            catch {
                "Unable to create new Teams channel '$($channel.Value.ChannelName)', $($teamsChannelBody | ConvertTo-Json -Depth 5), $($_.Exception.Message)"
            }
        }

        $historyResponse = Invoke-RestMethod -Uri $uris['History'] -Method Post -Body @{
            channel = $slackChannel.id
        }
        if (-not $historyResponse.ok) {
            "Unable to get history for channel '$($slackChannel.name)'. Error: '$($historyResponse.error)'."
            continue
        }

        $messages = [System.Collections.ArrayList]::new()
        $messages.AddRange(($historyResponse.messages | Where-Object { $_.type -eq "message" -and -not $_.subtype }))

        while ($historyResponse.has_more) {
            $historyResponse = Invoke-RestMethod -Uri $uris['History'] -Method Post -Body @{
                channel = $slackChannel.id
                latest  = $historyResponse.messages[-1].ts
            }
            $messagesToAdd = [array]($historyResponse.messages | Where-Object { $_.type -eq "message" -and -not $_.subtype })
            if ($messagesToAdd) { $messages.AddRange($messagesToAdd) }
            Start-Sleep -Milliseconds 50
        }
        
        $channelPath = Join-Path $pwd -ChildPath "MessageMigration/$($teamResponse.displayName)/$($channelResponse.displayName)"
        $messagePath = Join-Path $channelPath MessageQueue
        if (-not (Test-Path $channelPath)) {
            $null = New-Item -Path $channelPath -ItemType Directory -Force
        }
        if (-not (Test-Path $messagePath)) {
            $null = New-Item -Path $messagePath -ItemType Directory -Force
        }

        foreach ($message in $messages) {
            if ($channel.Value.ChannelType -eq 'standard') { continue } # Skip already processed
            if (-not $message.text -and $message.files) {
                continue
            }
            # profile.email
            $messageText = $message.text
            $messageTime = '{0:yyyyMMdd_HHmmss_fff}' -f (ConvertFrom-UnixTime -UnixTime $message.ts)

            $sendingSlacker = if ($slackUsers[$message.user].real_name) { $slackUsers[$message.user].real_name } else { 'UNKNOWN_USER' }
            $messageText = "Originally sent by $($sendingSlacker):`r`n`r`n{0}" -f $messageText

            $userMentions = @{}
            foreach ($mention in ($messageText | Select-String -Pattern "(<@([A-Z0-9]+)>)" -AllMatches).Matches) {
                $mentionUser = if ($slackUsers[$mention.Groups[2].Value]) { $slackUsers[$mention.Groups[2].Value].real_name } else { 'UNKNOWN_USER' }
                $messageText = $messageText.Replace($mention.Groups[1].Value, $mentionUser)
            }

            $messageText | Set-Content -Path (Join-Path $messagePath "$($messageTime)_$($sendingSlacker).txt")
        }

        Remove-Variable -Name contentDrive, channelFolder -ErrorAction SilentlyContinue

        $counter = 0
        while (-not $contentDrive) {
            $contentDrive = Invoke-GraphRequest -Query ($uris['TeamsDriveRefresh'] -f $teamResponse.id, $channelResponse.id) -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 5
            if ($counter -gt 10) {
                Write-Warning "no content drive available, skipping file upload in $($channelResponse.displayName)"
                break
            }
            $counter++
        }
        
        if (-not $contentDrive) {
            Write-Warning "SharePoint Drive not ready, skipping $($channelResponse.displayName)"
            continue
        }

        $counter = 0
        while (-not $channelFolder -and $channel.Value.ChannelType -eq 'private') {
            $channelFolder = Invoke-GraphRequest "drives/$($contentDrive.parentReference.driveid)/items/root:/$($channelResponse.displayName)" -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 5
            if ($counter -gt 10 -and $channel.Value.ChannelType -eq 'private') {
                Write-Warning "No content folder in account channel drive available, skipping file upload in $($channelResponse.displayName)"
                break
            }
            $counter++
        }
        
        if (-not $channelFolder -and $channel.Value.ChannelType -eq 'private') {
            Write-Warning "SharePoint channel drive not ready, skipping $($channelResponse.displayName)"
            continue
        }

        if (-not $channelFolder -and $channel.Value.ChannelType -eq 'standard') {
            $channelFolder = Invoke-GraphRequest "drives/$($contentDrive.parentReference.driveid)/items/root:/children" -Method Post -Body @{
                name                                = $($channelResponse.displayName)
                folder                              = @{ }
                "@microsoft.graph.conflictBehavior" = 'fail'
            } -ErrorAction SilentlyContinue
        }
        
        $messageFolder = Invoke-GraphRequest "drives/$($contentDrive.parentReference.driveid)/items/root:/$($channelResponse.displayName):/MessageImport" -ErrorAction SilentlyContinue
        if (-not $messageFolder) {
            $messageFolder = Invoke-GraphRequest "drives/$($contentDrive.parentReference.driveid)/items/root:/$($channelResponse.displayName):/children" -Method Post -Body @{
                name                                = "MessageImport"
                folder                              = @{ }
                "@microsoft.graph.conflictBehavior" = 'fail'
            } -ErrorAction SilentlyContinue
        }
        
        $fileFolder = Invoke-GraphRequest "drives/$($contentDrive.parentReference.driveid)/items/root:/$($channelResponse.displayName):/FileImport" -ErrorAction SilentlyContinue
        if (-not $fileFolder) {
            $fileFolder = Invoke-GraphRequest "drives/$($contentDrive.parentReference.driveid)/items/root:/$($channelResponse.displayName):/children" -Method Post -Body @{
                name                                = "FileImport"
                folder                              = @{ }
                "@microsoft.graph.conflictBehavior" = 'fail'
            } -ErrorAction SilentlyContinue
        }

        $messageFiles = foreach ($message in $messages) {
            # Channel is open for business
            if (-not $message.files) { continue }
            # Add all files as attachments
            # Download from Slack
            if ($null -eq $teamResponse.id) {
                $teamResponse = Invoke-GraphRequest ($uris['TeamFilter'] -f $team) -ErrorAction SilentlyContinue
            }
            if ($null -eq $channelResponse.id) {
                $channelResponse = Invoke-GraphRequest -Query ($uris['TeamChannelFilter'] -f $teamResponse.id, $channel.Value.ChannelName) -ErrorAction SilentlyContinue
            }

            if ($null -eq $teamResponse.id -or $null -eq $channelResponse.id) {
                Write-Warning "Skipping file upload, unable to find team or channel."
                continue
            }

            $messageTime = '{0:yyyyMMdd_HHmmss_fff}' -f (ConvertFrom-UnixTime -UnixTime $message.ts)
            $sendingSlacker = if ($slackUsers[$message.user].real_name) { $slackUsers[$message.user].real_name } else { 'UNKNOWN_USER' }

            foreach ($file in $message.files) {
                if ($null -eq $file.url_private_download) { continue }
                Invoke-RestMethod -Uri $file.url_private_download -OutFile (Join-Path -Path $channelPath "$($messageTime)_$($sendingSlacker)_$($file.name)")
            
                # Upload to new team
                Get-Item (Join-Path -Path $channelPath "$($messageTime)_$($sendingSlacker)_$($file.name)")
            }
        }

        foreach ($downloadedFile in $messageFiles) {
            $token = (Get-GraphToken).Token
            try {
                $null = Invoke-RestMethod -Method PUT -Uri "https://graph.microsoft.com/v1.0/drives/$($contentDrive.parentReference.driveid)/items/root:/$($channelResponse.displayName)/FileImport/$($downloadedFile.Name):/content" -InFile $downloadedFile.FullName -Headers @{ 
                    Authorization  = "Bearer $token"
                    'Content-Type' = 'text/plain'
                } -ErrorAction Stop
                $downloadedFile.FullName | Remove-Item
            }
            catch {
                Write-Warning "Skipping file upload of $($downloadedFile.FullName) due to errors: $($_.Exception.Message)"
            }
        }

        foreach ($downloadedFile in (Get-ChildItem (Join-Path $channelPath "MessageQueue/*.txt"))) {
            $token = (Get-GraphToken).Token
            try {
                $null = Invoke-RestMethod -Method PUT -Uri "https://graph.microsoft.com/v1.0/drives/$($contentDrive.parentReference.driveid)/items/root:/$($channelResponse.displayName)/MessageImport/$($downloadedFile.Name):/content" -InFile $downloadedFile.FullName -Headers @{ 
                    Authorization  = "Bearer $token"
                    'Content-Type' = 'text/plain'
                } -ErrorAction Stop
                $downloadedFile.FullName | Remove-Item
            }
            catch {
                Write-Warning "Skipping file upload of $($downloadedFile.FullName) due to errors: $($_.Exception.Message)"
            }
        }
    }
}
