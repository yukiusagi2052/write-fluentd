
## Pester >>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
. "$here\$sut"
## << Paster



# スクリプト本体の読み込み
. ("{0}\write-fluentd.ps1" -f (Split-Path $MyInvocation.MyCommand.Path -Parent))

# テスト用fluentdサーバー
$ServerUri = 'http://ls6:9880/'
$DebugTag = 'debug.pester'

# テスト・オブジェクト生成 function定義
Function Make-MultiTestObject {
	param
	(
		[Int] $ObjectsCount = 3 # テストで生成するオブジェクト数
	)
    [System.Management.Automation.PSObject[]] $Objects = @()


    For($i=1; $i -le $ObjectsCount; $i++)
    {
        $Objects += New-Object PSObject -Property @{
            Name = "temperature"
			Location = "Tokyo"
            MesuerdTime = [String] ( ([DateTime]::Now).AddSeconds(-(Get-Random 100)).ToString("yyyy/MM/dd HH:mm:ss") )
            OutsideTemp = [float]( (Get-Random 200) / 10 - (Get-Random 200) / 10 )
            InsideTemp = [float]( 10 + (Get-Random 100) / 10)
        }

        $Objects += New-Object PSObject -Property @{
            Name = "temperature"
			Location = "Osaka"
            MesuerdTime = [String] ( ([DateTime]::Now).AddSeconds(-(Get-Random 100)).ToString("yyyy/MM/dd HH:mm:ss") )
            OutsideTemp = [float]( (Get-Random 200) / 10 - (Get-Random 200) / 10 )
            InsideTemp = [float]( 10 + (Get-Random 100) / 10)
        }


        $Objects += New-Object PSObject -Property @{
            Name = "temperature"
			Location = "Fukuoka"
            MesuerdTime = [String] ( ([DateTime]::Now).AddSeconds(-(Get-Random 100)).ToString("yyyy/MM/dd HH:mm:ss") )
            OutsideTemp = [float]( (Get-Random 200) / 10 - (Get-Random 200) / 10 )
            InsideTemp = [float]( 10 + (Get-Random 100) / 10)
        }

    }

    Write-Output $Objects
}

Function Make-SingleTestObject {

    New-Object PSObject -Property @{
            #Name = "temperature"
			Location = "Tokyo"
            #MesuerdTime = [String] ( ([DateTime]::Now).AddSeconds(-(Get-Random 100)).ToString("yyyy/MM/dd HH:mm:ss") )
            OutsideTemp = [float]( (Get-Random 200) / 10 - (Get-Random 200) / 10 )
            InsideTemp = [float]( 10 + (Get-Random 100) / 10)
    }

}

Describe "Test-Environment" {
    It "Post a sigle data to fluentd" {
		Invoke-RestMethod `
			-Uri ("{0}{1}" -f $ServerUri,$DebugTag) `
			-Method POST `
			-Body 'json={"action":"login","user":3}' `
        | Should BeNullOrEmpty
    }

    It "Post multiple data (batch mode) to fluentd" {
		Invoke-RestMethod `
			-Uri ("{0}{1}" -f $ServerUri,$DebugTag) `
			-Method POST `
			-Body 'json=[{"action":"login","user":11},{"action":"login","user":12}]' `
        | Should BeNullOrEmpty
	}
}

Describe "Invoke-HttpPost" {
    It "json include only ASCII character" {
        Invoke-HttpPost `
          -URI ("{0}{1}" -f $ServerUri,$DebugTag) `
          -Body 'json={"InsideTemp":11.9,"time":"2001-01-01T01:01:01.0000000","Name":"temperature","OutsideTemp":7}' `
        | Should Be $true
    }

    It "json-value include not ASCII character" {
        Invoke-HttpPost `
          -URI ("{0}{1}" -f $ServerUri,$DebugTag) `
          -Body 'json={"InsideTemp":11.9,"time":"2001-01-01T01:01:01.0000000","Name":"温度","OutsideTemp":7}' `
        | Should Be $true
    }

    It "json-key include not ASCII character" {
        Invoke-HttpPost `
          -URI ("{0}{1}" -f $ServerUri,$DebugTag) `
          -Body 'json={"屋内温度":11.9,"time":"2001-01-01T01:01:01.0000000","名称":"temperature","屋外温度":7}' `
        | Should Be $true
    }

}

Describe "write-fluentd single" {
    It "post test" {
        Make-SingleTestObject `
        | write-fluentd -Server $ServerUri `
                         -tag 'influxdb.temperature' `
                         -Values ('InsideTemp','OutsideTemp')  | Should Be $true
    }
}


Describe "write-fluentd multi" {
    It "post test" {
        Make-MultiTestObject `
        | write-fluentd -Server $ServerUri `
                         -tag 'influxdb.temperature' `
                         -Values ('InsideTemp','OutsideTemp') | Should Be $true
    }
}

<#
Describe "write-fluentd-err" {
    It "no data" {
       $null `
         | write-fluentd -Server $ServerUri `
                         -tag 'debug' `
                         -Strings ('Name') `
                         -Time "MesuerdTime" `
         | Should Be $false
    }
	
    It "miss match data" {
           write-fluentd -Server $ServerUri `
                         -tag 'debug' `
                         -Strings ('Name') `
                         -Time "MesuerdTime" `
                         -Data (Make-TestObject) `
         | Should Be  $false
    }
	
}
#>
