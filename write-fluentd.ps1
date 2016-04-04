# << Define Script Local Functions and Variables >>

# Unix Epoch Time �
[DateTime] $EpochOrigin = "1970/01/01 00:00:00"


[Int] $PostRequestTimeout = 3 * 1000 #���N�G�X�g�E�^�C���A�E�g�ims�j
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
		$PostBody.Remove( ($PostBody.Length - 2), 1) > $Null # ������Ō�� ","���폜
		$PostBody.Append(']') > $Null

		# �f�o�b�O�p
		write-host $PostBody.ToString()

		# Powershell 3.0�ȏ�
		#�@Invoke-RestMethod -Uri $PostURI.ToString() -Method POST -Body $PostBody.ToString()

		# Powershell 2.0�ȏ�
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
	$JSONL.Remove( ($JSONL.Length - 1), 1) > $Null # ������Ō�� ","���폜
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
	
	#�f�o�b�O�p
	#Write-Host "called Invoke-HttpPost"
	
	#�`�F�b�N�t���O
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
			
			# �f�o�b�O�p
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
				
				# �f�o�b�O�p
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

		# ���� �����E���s��Ԃ�
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

		# <���㌟��>
		# TagKey �^�O�Ɋ��蓖�Ă�v���p�e�B��
		# TagPrefix TagKey���w�肵���Ƃ��̃v���t�B�b�N�X�Ƃ��镶����
	)

	Begin
	{
		# �f�o�b�O�p
		#Write-Host "Called wtite-fluentd(Begin)"

		# Post URI
		[System.Text.StringBuilder] $PostURI = New-Object System.Text.StringBuilder( 8192 )

		# making URI
		$PostURI.Append($Server) > $Null
		$PostURI.Append($tag) > $Null

		# $PostURI.Clear() > $Null
		# �f�o�b�O�p
		#Write-Host ("{0}" -f $posturi.ToString() )

		#
		# ����������
		#
		PostBody-Init
	}

	Process
	{
		#
		# pipe���ꂽ�e�I�u�W�F�N�g���������郁�C������
		#

		# �f�o�b�O�p
		#Write-Host "Called wtite-fluentd(Process)"

		Try
		{
			# �p�C�v�ŁA�I�u�W�F�N�g���n���ꂽ���`�F�b�N
			If( $Data -eq $Null ){
				Write-Error "There is no piped object."
				Write-Output $False
				return
			}

			# <ToDo> -Data �ł͒P��I�u�W�F�N�g[PSObject]��z�肵�Ă��邽�߁A
			# �I�u�W�F�N�g�z��[PSObject[]]�ł������ꍇ�́A�G���[��Ԃ�
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
				# �p�����[�^ -StringPropertys �̎w��L��ꍇ
				If ( ($Strings -ne $Null) -and ($Strings.Length -ne 0) )
				{
					If ( $Strings -contains ($Prop.Name) )
					{
						# StringPropertys�Ƃ��Ďw�肳�ꂽ�v���p�e�B�́AJSONL�ɕ�����Ƃ��Ēǉ�
						Jsonl-Add-StringElement -Key $Prop.Name -Value ( $Data.($Prop.Name).ToString() ) #������
						continue
					}
				}

				# �p�����[�^�[ -TimeKey �̎w��L��ꍇ
				If ( ($Time -ne $Null) -and ($Time.Length -ne 0) )
				{
					If ( $Time -contains ($Prop.Name) )
					{
						# ���Ԃ������v���p�e�B�́AJSONL��UnixEpoch�`���̎����Ƃ��Ēǉ�
						Jsonl-Add-ValueElement -Key 'time' -Value (ConvertTo-UnixEpoch ( $Data.($Prop.Name) ) )
						#Jsonl-Add-StringElement -Key 'datetime' -Value (ConvertTo-ISO8601 ( $Data.($Prop.Name) ) )
						continue
					}
				}

				# ����ȊO�̃v���p�e�B�́AJSONL�ɐ��l�Ƃ��Ēǉ�
				Jsonl-Add-ValueElement -Key $Prop.Name -Value ( $Data.($Prop.Name).ToString() ) #�񕶎���

			}

			# �p�����[�^�[ -TimeKey �̎w�肪�����ꍇ�A���ݎ�����ݒ�
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
		# �f�o�b�O�p
		#Write-Host "Called wtite-fluentd(End)"

		PostBody-Commit

		Write-Output $WriteFluentdResult
	}

}

