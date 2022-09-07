function Get-ShowID{
    param (
        $ShowData,
        $PlexShows
    ) 
    $ratingKey = $ShowData.ratingKey        
    # If new ID type, collect from TVDB
    if($ShowData.guid -like 'plex*'){            
        try {
            $Results = (Invoke-RestMethod -Uri "https://api.thetvdb.com/search/series?name=$($ShowData.title -replace "& ")" -Headers $TVDBHeaders)
            $PotentialShows = $Results.data
            
            for(($i = 0); $i -lt [Math]::Min($PotentialShows.Length, 10); $i++){
                $dateData = $PotentialShows[$i].firstAired -split "-" 
                if($ShowData.year -eq $dateData[0]){
                    $GUID = $PotentialShows[$i].id
                    break
                }
                
            }
            if($GUID -eq ""){
                Write-Output("No Match found for $($ShowData.title)")
                $GUID = $PotentialShows[0].id
            } 
        } catch {
            Write-Warning "Failed to get correct ID for $($ShowData.title)"
	    
        }
    }else{
        $GUID = $ShowData.guid -replace ".*//(\d+).*",'$1'
    }
    # Add GUID to shows
    if ($PlexShows.ContainsKey($GUID)) {
        [void]$PlexShows[$GUID]["ratingKey"].Add($ratingKey)
        Write-Output("Multiple same GUID")
    } else {
        [void]$PlexShows.Add($GUID,@{
            "title" = $ShowID.title
            "ratingKey" = [System.Collections.Generic.List[int]]::new()
            "seasons" = @{}
        })
        [void]$PlexShows[$GUID]["ratingKey"].Add($ratingKey)
    }
    $GUID
}

function Get-ShowSeasons{
    param (
        $GUID,
        $PlexShows
    )   
    ForEach ($RatingKey in $PlexShows[$GUID]["ratingKey"]) {
        $Episodes = (Invoke-RestMethod -Uri "$PlexServer/library/metadata/$RatingKey/allLeaves" -Headers $PlexHeaders).MediaContainer.Video
        $Seasons = $Episodes.parentIndex | Sort-Object -Unique
        ForEach ($Season in $Seasons) {
            if (!($PlexShows[$GUID]["seasons"] -contains $Season)) {
                $PlexShows[$GUID]["seasons"][$Season] = [System.Collections.Generic.List[hashtable]]::new()
            }
        }
        ForEach ($Episode in $Episodes) {
            if ((!$Episode.parentIndex) -or (!$Episode.index)) {
                Write-Host -ForegroundColor Red "Missing parentIndex or index"
                Write-Host $PlexShows[$GUID]
                Write-Host $Episode
            } else {
                [void]$PlexShows[$GUID]["seasons"][$Episode.parentIndex].Add(@{$Episode.index = $Episode.title})
            }
        }
    }
}


function Get-MissingEpisodes{
    param (
        $GUID,
        $PlexShows,
        $MissingArray
    ) 

    $Page = 1
    try {
        $Results = (Invoke-RestMethod -Uri "https://api.thetvdb.com/series/$GUID/episodes?page=$page" -Headers $TVDBHeaders)
        $Episodes = $Results.data
        while ($Page -lt $Results.links.last) {
            $Page++
            $Results = (Invoke-RestMethod -Uri "https://api.thetvdb.com/series/$GUID/episodes?page=$page" -Headers $TVDBHeaders)
            $Episodes += $Results.data
        }
    } catch {
        Write-Warning "Failed to get Episodes for $($PlexShows[$GUID]["title"])"
	    $Episodes = $null
    }
    ForEach ($Episode in $Episodes) {
        # ignore unaired or incorrect episodes
        if (!$Episode.airedSeason) { continue }
        if ($Episode.airedSeason -eq 0) { continue }
        if (!$Episode.firstAired) { continue }
		if ($Episode.firstAired -eq "0000-00-00"){
			$tempText = "S{0:00}E{1:00} is null" -f [int]$Season,[int]$Episode.airedEpisodeNumber
			Write-Warning "Airdate for $($PlexShows[$GUID]["title"]) $($tempText)" 
			continue
		}
        # Ignore if not aired within desired time span        
		if ((Get-Date $Episode.firstAired) -gt (Get-Date).AddDays($MissingArray.Length-2)) { continue }
        
        # If episode not found in plex
        if (!($PlexShows[$GUID]["seasons"][$Episode.airedSeason.ToString()].Values -contains $Episode.episodeName)) {
	        if (!($PlexShows[$GUID]["seasons"][$Episode.airedSeason.ToString()].Keys -contains $Episode.airedEpisodeNumber)) {
                
                for($i = -1; $i -lt ($MissingArray.Length-1); $i++){
                    if ((Get-Date $Episode.firstAired) -lt (Get-Date).AddDays($i)) {               
					    if (!$MissingArray[$i+1].ContainsKey($PlexShows[$GUID]["title"])) {
                        $MissingArray[$i+1][$PlexShows[$GUID]["title"]] = [System.Collections.Generic.List[hashtable]]::new()
					    }
					    [void]$MissingArray[$i+1][$PlexShows[$GUID]["title"]].Add(@{
						    "airedSeason" = $Episode.airedSeason.ToString()
						    "airedEpisodeNumber" = $Episode.airedEpisodeNumber.ToString()
						    "episodeName" = $Episode.episodeName
						    "airedDate" = $Episode.firstAired
                        
					    })
                    break
                }
                }			
				
                
	        }
        }
    }
}