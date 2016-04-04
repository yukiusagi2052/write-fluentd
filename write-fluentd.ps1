# << Define Script Local Functions and Variables >>


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
			[String[]] $Values,
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
				# パラメータ -Values の指定有る場合
				If ( ($Values -ne $Null) -and ($Values.Length -ne 0) )
				{
					If ( $Values -contains ($Prop.Name) )
					{
						# Valuesで指定されたプロパティは、JSONLに""で括らずに（数値扱い）追加
						Jsonl-Add-ValueElement -Key $Prop.Name -Value ( $Data.($Prop.Name).ToString() ) #数値扱い
						continue
					}
				}

				# それ以外のプロパティは、JSONLに""で括って（文字列扱い）追加
				Jsonl-Add-StringElement -Key $Prop.Name -Value ( $Data.($Prop.Name).ToString() ) 

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

