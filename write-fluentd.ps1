# << Define Script Local Functions and Variables >>
[Int] $PostRequestTimeout = 3 * 1000 #リクエスト・タイムアウト（ms）

# Json Data Buffer
[System.Text.StringBuilder] $PostBuffer = New-Object System.Text.StringBuilder( 8192 )

Function PostBody-Commit
{

	# デバッグ用
	write-host $PostBuffer.ToString()

	# Powershell 2.0以上
	Invoke-HttpPost -Uri $PostURI.ToString() -Body $PostBuffer.ToString() > $Null

	$PostBuffer.Remove(0,$PostBuffer.length) > $Null

}


Function Jsonl-Start-Object
{
	$PostBuffer.Remove(0,$PostBuffer.length) > $Null
	$PostBuffer.Append('json={') > $Null
}

Function Jsonl-Add-StringElement
{
	Param
	(
		[String] $Key,
		[String] $Value
	)
	# making... "action":"login"
	$PostBuffer.Append('"') > $Null
	$PostBuffer.Append($Key) > $Null
	$PostBuffer.Append('":"') > $Null
	$PostBuffer.Append($Value) > $Null
	$PostBuffer.Append('"') > $Null
	$PostBuffer.Append(',') > $Null
}

Function Jsonl-Add-ValueElement
{
	Param
	(
		[String] $Key,
		[String] $Value
	)
	# making... "user":3
	$PostBuffer.Append('"') > $Null
	$PostBuffer.Append($Key) > $Null
	$PostBuffer.Append('":') > $Null
	$PostBuffer.Append($Value) > $Null
	$PostBuffer.Append(',') > $Null
}

Function Jsonl-End-Object
{
	$PostBuffer.Remove( ($PostBuffer.Length - 1), 1) > $Null # 文字列最後の ","を削除
	$PostBuffer.Append('}') > $Null
}

function Invoke-HttpPost {
	[CmdletBinding()]
	Param
	(
		[string] $URI,
		[string] $Body
	)
	
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
			[String] $server,
		[Parameter(Mandatory=$true, Position=1)]
			[String] $tag,
		[Parameter(Position=2)]
			[String[]] $values,
		[Parameter(Mandatory=$true, ValueFromPipeline=$true)]
			[System.Management.Automation.PSObject] $Data
	)

	Begin
	{
		# Post URI
		[System.Text.StringBuilder] $PostURI = New-Object System.Text.StringBuilder( 8192 )

		# making URI
		$PostURI.Append($server) > $Null
		$PostURI.Append($tag) > $Null

		$PostBuffer.Remove(0,$PostBuffer.length) > $Null
	}

	Process
	{
		#
		# pipeされた各オブジェクトを処理するメイン処理
		#


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

			[Bool] $PostBufferHealth > $Null
			Jsonl-Start-Object

			$Props = $Data | Get-Member -MemberType NoteProperty

			ForEach ($Prop in $Props)
			{
				# パラメータ -Values の指定有る場合
				If ( ($values -ne $Null) -and ($values.Length -ne 0) )
				{
					If ( $values -contains ($Prop.Name) )
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
			$PostBufferHealth = $True

		} Catch [Exception] {
			$PostBufferHealth = $False
			Write-Error $Error[0].Exception.ErrorRecord
			throw $_.Exception
		}

		If ( $PostBufferHealth )
		{
			PostBody-Commit
		}
	}

	End
	{
	}

}

