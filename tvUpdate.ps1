# Load auth
. ./secrets.ps1

#Load function
. ./tvUpdateFunctions.ps1

# Titles to ignore
$IgnoredTitles = Get-Content -Path .\ignoredTitles.txt

# Headers
$PlexHeaders = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$PlexHeaders.Add("Authorization","Basic $([System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$PlexUsername`:$PlexPassword")))")
$PlexHeaders.Add("X-Plex-Client-Identifier","MissingTVEpisodes")

$TVDBHeaders = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$TVDBHeaders.Add("Accept", "application/json")

# Collect tokens
try {
    $PlexToken = (Invoke-RestMethod -Uri 'https://plex.tv/users/sign_in.json' -Method Post -Headers $PlexHeaders).user.authToken
    $PlexHeaders.Add("X-Plex-Token",$PlexToken)
    [void]$PlexHeaders.Remove("Authorization")
    $TVDBToken = (Invoke-RestMethod -Uri "https://api.thetvdb.com/login" -Method Post -Body ($TVDBAuth | ConvertTo-Json) -ContentType 'application/json').token
    $TVDBHeaders.Add("Authorization", "Bearer $TVDBToken")
} catch {
    Write-Host -ForegroundColor Red "Failed to collect tokens"
    Write-Host -ForegroundColor Red $_
    break
}

# Collect Libs
try {
    $LibIDs = ((Invoke-RestMethod -Uri "$PlexServer/library/sections" -Headers $PlexHeaders).MediaContainer.Directory | Where-Object { $_.type -eq "show" }).key
    
} catch {
    Write-Host -ForegroundColor Red "Failed to get libs"    
    break
}


$PlexShows = @{}
$MissingArray = @(@{}::new(6))
# Collect info
ForEach ($LibID in $LibIDs) { 
    $LibShows = (Invoke-RestMethod -Uri "$PlexServer/library/sections/$LibID/all/" -Headers $PlexHeaders).MediaContainer.Directory
    $Progress = 0
    ForEach ($ShowID in $LibShows) {
        if (-not $IgnoredTitles.Contains($ShowID.title)) { 
            $Progress++
            Write-Progress -Activity "Collecting Show Data in: $($LibID)" -Status $ShowID.title -PercentComplete ($Progress / $LibShows.Count * 100)

            #Collect show info
            $GUID = Get-ShowID -ShowData $ShowID -PlexShows $PlexShows
            Get-ShowSeasons -GUID $GUID -PlexShows $PlexShows  
            Get-MissingEpisodes -GUID $GUID -PlexShows $PlexShows -MissingArray $MissingArray          
        }
    }
}

#Export missing info
$compText = "Buffer `n"
$count = 0
ForEach($missArray in $MissingArray){
    if($count -eq 1){
        $compText = $compText + "## Tomorrow:" + "\n"
    }elseif($count -gt 1){
        $compText = $compText + "## " + ((get-date).AddDays($count).DayOfWeek) + "\n"
    }
    ForEach ($Show in ($missArray.Keys | Sort-Object)) {
        $textString = $Show + " -"
        $showStringLink = $Show -replace " ", "+"
        ForEach ($Season in ($missArray[$Show].airedSeason | Sort-Object -Unique)) {
            $Episodes = $missArray[$Show] | Where-Object { $_.airedSeason -eq $Season }
            ForEach ($Episode in $Episodes) {
			    $episodeString = "S{0:00}E{1:00}" -f [int]$Season,[int]$Episode.airedEpisodeNumber       
                $textString = $textString + " [" + $episodeString + "]" + "(https://rarbg.to/torrents.php?search=" + $showStringLink + "+" + $episodeString + "&order=seeders&by=DESC" + ")"

            }
        }
	    $compText = $compText + $textString + "\n"
    }
    $count++
}
$compText