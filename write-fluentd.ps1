
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
			[String[]] $text,
		[Parameter(Mandatory=$true, ValueFromPipeline=$true)]
			[System.Management.Automation.PSObject] $Data
	)

	Begin
	{
		# << Define Script Local Functions and Variables >>
		[Int] $PostRequestTimeout = 3 * 1000 #���N�G�X�g�E�^�C���A�E�g�ims�j

		Function PostBody-Commit
		{
			# �f�o�b�O�p
			Write-Verbose ($PostBuffer.ToString())

			# Powershell 2.0�ȏ�
			Invoke-HttpPost -Uri $PostURI -Body $PostBuffer.ToString() > $Null

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
			$PostBuffer.Remove( ($PostBuffer.Length - 1), 1) > $Null # ������Ō�� ","���폜
			$PostBuffer.Append('}') > $Null
		}

		function Invoke-HttpPost
		{
			[CmdletBinding()]
			Param
			(
				[string] $URI,
				[string] $Body
			)
	
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
			}
			Finally
			{
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
					Write-Verbose ("{0}: {1}" -f [int]$resp.StatusCode, $resp.StatusCode)

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
						Write-Verbose ("{0}: {1}" -f [int]$err.StatusCode, $err.StatusCode)
				
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

		# Json Data Buffer
		[System.Text.StringBuilder] $PostBuffer = New-Object System.Text.StringBuilder( 8192 )
		$PostBuffer.Remove(0,$PostBuffer.length) > $Null

		# Post URI
		[String] $PostURI = ("{0}{1}" -f $server, $tag)
		Write-Verbose $PostURI
	}

	Process
	{
		#
		# pipe���ꂽ�e�I�u�W�F�N�g���������郁�C������
		#


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

			[Bool] $PostBufferHealth > $Null
			Jsonl-Start-Object

			$Props = $Data | Get-Member -MemberType NoteProperty

			ForEach ($Prop in $Props)
			{
				# �p�����[�^ -text �̏ꍇ
				If ( ($text -ne $Null) -and ($text.Length -ne 0) )
				{
					If ( $text -contains ($Prop.Name) )
					{
						# �v���p�e�B�̒l���A""�Ŋ����āi�����񈵂��jJSON�֒ǉ�
						Jsonl-Add-StringElement -Key $Prop.Name -Value ( $Data.($Prop.Name).ToString() ) 
						continue
					}
				}
				# �v���p�e�B�̒l���A""�Ŋ��炸�Ɂi���l�����jJSON�֒ǉ�
				Jsonl-Add-ValueElement -Key $Prop.Name -Value ( $Data.($Prop.Name).ToString() )
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

