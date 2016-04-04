# << Define Script Local Functions and Variables >>

# Unix Epoch Time 基準
[DateTime] $EpochOrigin = "1970/01/01 00:00:00"


[Int] $PostRequestTimeout = 3 * 1000 #リクエスト・タイムアウト（ms）
[Long] $PostBodyMaxSize = 1 * 1024 * 1024 #1MB 

# Function Result
[Bool] $WriteFluentdResult = $true

# Post Body Buffer
[System.Text.StringBuilder] $PostBody = New-Object System.Text.StringBuilder( $PostBodyMaxSize )

# JSONL Working Buffer
[System.Text.StringBuilder] $JSONL = New-Object System.Text.StringBuilder( 1024 )


# Preparating Buffer from multiple Data, And bulk posting to Fluentd
Function PostBody-Add
{
	Param([String] $Jsonl)

	If( ($PostBody.Length + $Jsonl.Length ) -gt $PostBodyMaxSize )
	{
		#Once Writing Buffer to Fluend
		PostBody-Commit
		PostBody-Init
	} 

	$PostBody.Append("$Jsonl") > $Null
	$PostBody.Append(",`n") > $Null

}

Function PostBody-Init
{
	$PostBody.Clear() > $Null
	$PostBody.Append('json=[') > $Null
	$PostBody.Append("`n") > $Null
}

Function PostBody-Commit
{
	If ($PostBody.Length -gt 6)
	{
		$PostBody.Remove( ($PostBody.Length - 2), 1) > $Null # 文字列最後の ","を削除
		$PostBody.Append(']') > $Null

		# デバッグ用
		write-host $PostBody.ToString()

		# Powershell 3.0以上
		#　Invoke-RestMethod -Uri $PostURI.ToString() -Method POST -Body $PostBody.ToString()

		# Powershell 2.0以上
		If(-Not(Invoke-HttpPost -Uri $PostURI.ToString() -Body $PostBody.ToString() ))
		{
			$WriteFluentdResult = $False
		}
	}
}


Function Jsonl-Start-Object
{
	$JSONL.Clear() > $Null
	$JSONL.Append('{') > $Null
}

Function Jsonl-Add-StringElement
{
	Param
	(
		[String] $Key,
		[String] $Value
	)
	# making... "action":"login"
	$JSONL.Append('"') > $Null
	$JSONL.Append($Key) > $Null
	$JSONL.Append('":"') > $Null
	$JSONL.Append($Value) > $Null
	$JSONL.Append('"') > $Null
	$JSONL.Append(',') > $Null
}

Function Jsonl-Add-ValueElement
{
	Param
	(
		[String] $Key,
		[String] $Value
	)
	# making... "user":3
	$JSONL.Append('"') > $Null
	$JSONL.Append($Key) > $Null
	$JSONL.Append('":') > $Null
	$JSONL.Append($Value) > $Null
	$JSONL.Append(',') > $Null
}

Function Jsonl-End-Object
{
	$JSONL.Remove( ($JSONL.Length - 1), 1) > $Null # 文字列最後の ","を削除
	$JSONL.Append('}') > $Null
}

Function ConvertTo-UnixEpoch
{
	Param( [System.Object] $DateTime )

	Try{
		# return unix epoch time
		(New-TimeSpan -Start (Get-Date $EpochOrigin) -End (Get-Date ([DateTime] $DateTime))).Totalseconds
	} Catch {
		Write-Error $Error[0].Exception.ErrorRecord
		throw $_.Exception
	}
}


function Invoke-HttpPost {
	[CmdletBinding()]
	Param
	(
		[string] $URI,
		[string] $Body
	)
	
	#デバッグ用
	#Write-Host "called Invoke-HttpPost"
	
	#チェックフラグ
	[Bool] $MethodResult = $True

	[System.Net.HttpWebRequest]$HttpWebRequest = [System.Net.WebRequest]::Create($URI)
	$HttpWebRequest.ContentType = "application/x-www-form-urlencoded"
	$BodyStr = [System.Text.Encoding]::UTF8.GetBytes($Body)
	$HttpWebrequest.ContentLength = $BodyStr.Length
	$HttpWebRequest.ServicePoint.Expect100Continue = $false
	$HttpWebRequest.Timeout = $PostRequestTimeout
	$HttpwebRequest.Method = "POST"

	# [System.Net.WebRequest]::GetRequestStream()
	# [System.IO.Stream]::Write()
	Try
	{
		[System.IO.Stream] $RequestStream = $HttpWebRequest.GetRequestStream()
		$RequestStream.Write($BodyStr, 0, $BodyStr.length)
		$MethodResult = $True
	}
	Catch [System.Net.WebException]
	{
		$WebException = $_.Exception
		Write-Host ("{0}: {1}" -f $WebException.Status, $WebException.Message)
		$MethodResult = $False
	}
	Catch [Exception]
	{
		Write-Error $Error[0].Exception.ErrorRecord
		$MethodResult = $False
	} Finally {
		If ($RequestStream -ne $Null)
		{
			$RequestStream.Close()
		}
	}


	# [System.Net.WebRequest]::GetResponse()
	If($MethodResult)
	{
		Try
		{
			[System.Net.HttpWebResponse] $resp = $HttpWebRequest.GetResponse();
			
			# デバッグ用
			Write-Host ("{0}: {1}" -f [int]$resp.StatusCode, $resp.StatusCode)

			$resp.Close()
			$MethodResult = $True
		}
		Catch [System.Net.WebException]
		{
			$ErrResp = $_.Exception.Response
			If ($ErrResp -ne $Null)
			{
				[System.Net.HttpWebResponse]$err = $ErrResp
				
				# デバッグ用
				Write-Host ("{0}: {1}" -f [int]$err.StatusCode, $err.StatusCode)
				
				$ErrResp.Close()
			}
			$MethodResult = $False
		}
		Catch [Exception]
		{
			Write-Error $Error[0].Exception.ErrorRecord
			$MethodResult = $False
		}

		# 処理 成功・失敗を返す
		Write-Output $MethodResult

	}

}


Function write-fluentd
{
	[CmdletBinding()]
	Param
	(
		[Parameter(Mandatory=$true, Position=0)]
			[String] $Server,
		[Parameter(Mandatory=$true, Position=1)]
			[String] $tag,
		[Parameter(Position=2)]
			[String[]] $Strings,
		[Parameter(Position=3)]
			[String] $Time,
		[Parameter(Mandatory=$true, ValueFromPipeline=$true)]
			[System.Management.Automation.PSObject] $Data

		# <今後検討>
		# TagKey タグに割り当てるプロパティ名
		# TagPrefix TagKeyを指定したときのプレフィックスとする文字列
	)

	Begin
	{
		# デバッグ用
		#Write-Host "Called wtite-fluentd(Begin)"

		# Post URI
		[System.Text.StringBuilder] $PostURI = New-Object System.Text.StringBuilder( 8192 )

		# making URI
		$PostURI.Append($Server) > $Null
		$PostURI.Append($tag) > $Null

		# $PostURI.Clear() > $Null
		# デバッグ用
		#Write-Host ("{0}" -f $posturi.ToString() )

		#
		# 初期化処理
		#
		PostBody-Init
	}

	Process
	{
		#
		# pipeされた各オブジェクトを処理するメイン処理
		#

		# デバッグ用
		#Write-Host "Called wtite-fluentd(Process)"

		Try
		{
			# パイプで、オブジェクトが渡されたかチェック
			If( $Data -eq $Null ){
				Write-Error "There is no piped object."
				Write-Output $False
				return
			}

			# <ToDo> -Data では単一オブジェクト[PSObject]を想定しているため、
			# オブジェクト配列[PSObject[]]であった場合は、エラーを返す
			If( $Data -is [System.Array] ){
				Write-Error "It is not an Object. (Objects array)"
				Write-Output $False
				return
			}

			[Bool] $JsonlHealth > $Null
			Jsonl-Start-Object

			$Props = $Data | Get-Member -MemberType NoteProperty

			ForEach ($Prop in $Props)
			{
				# パラメータ -StringPropertys の指定有る場合
				If ( ($Strings -ne $Null) -and ($Strings.Length -ne 0) )
				{
					If ( $Strings -contains ($Prop.Name) )
					{
						# StringPropertysとして指定されたプロパティは、JSONLに文字列として追加
						Jsonl-Add-StringElement -Key $Prop.Name -Value ( $Data.($Prop.Name).ToString() ) #文字列
						continue
					}
				}

				# パラメーター -TimeKey の指定有る場合
				If ( ($Time -ne $Null) -and ($Time.Length -ne 0) )
				{
					If ( $Time -contains ($Prop.Name) )
					{
						# 時間を示すプロパティは、JSONLにUnixEpoch形式の時刻として追加
						Jsonl-Add-ValueElement -Key 'time' -Value (ConvertTo-UnixEpoch ( $Data.($Prop.Name) ) )
						#Jsonl-Add-StringElement -Key 'datetime' -Value (ConvertTo-ISO8601 ( $Data.($Prop.Name) ) )
						continue
					}
				}

				# それ以外のプロパティは、JSONLに数値として追加
				Jsonl-Add-ValueElement -Key $Prop.Name -Value ( $Data.($Prop.Name).ToString() ) #非文字列

			}

			# パラメーター -TimeKey の指定が無い場合、現在時刻を設定
			If ( ($Time -eq $Null) -or ($Time.Length -eq 0) )
			{
				Jsonl-Add-ValueElement -Key 'time' -Value (ConvertTo-UnixEpoch ([DateTime]::Now) )
				#Jsonl-Add-StringElement -Key 'datetime' -Value (ConvertTo-ISO8601 ([DateTime]::Now) )				
			}

			Jsonl-End-Object
			$JsonlHealth = $True

		} Catch [Exception] {
			$JsonlHealth = $False
			Write-Error $Error[0].Exception.ErrorRecord
			throw $_.Exception
		}

		If ( $JsonlHealth )
		{
			PostBody-Add -Jsonl $JSONL.ToString()
		}
	}

	End
	{
		# デバッグ用
		#Write-Host "Called wtite-fluentd(End)"

		PostBody-Commit

		Write-Output $WriteFluentdResult
	}

}

