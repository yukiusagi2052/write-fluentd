
## Pester >>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
. "$here\$sut"
## << Paster



# スクリプト本体の読み込み
. ("{0}\write-fluentd.ps1" -f (Split-Path $MyInvocation.MyCommand.Path -Parent))


# テスト用オブジェクト生成
Function Make-TestObject {

	[System.Management.Automation.PSObject[]] $Objects = @()

	# テストで生成するオブジェクト数
	$ObjectsCount = 5

	For($i=1; $i -le $ObjectsCount; $i++)
	{
		$Objects += New-Object PSObject -Property @{
			Name = "temperature"
			MesuerdTime = [String] ( ([DateTime]::Now).ToString("yyyy/MM/dd HH:mm:ss") )
			OutsideTemp = [float]( (Get-Random 200) / 10 - (Get-Random 200) / 10 )
			InsideTemp = [float]( 10 + (Get-Random 100) / 10)
		}
		#生成時間をずらずため
		Start-Sleep -Milliseconds (Get-Random 500)
	}

	Write-Output $Objects
}


Describe "general" {
    It "no data" {
       "" `
		 | write-fluentd -Server 'http://ls6:9880/' `
		                 -tag 'influxdb.test4' `
		                 -Strings ('Name') `
		                 -Time "MesuerdTime" `
         | Should Be "There is no piped object."
    }

    It "miss match data" {
		   write-fluentd -Server 'http://ls6:9880/' `
		                 -tag 'influxdb.test4' `
		                 -Strings ('Name') `
		                 -Time "MesuerdTime" `
                         -Data (Make-TestObject) `
         | Should Be "It is not an Object. (Objects array)"
    }
}


Describe "Influxdb" {
    It "post test" {
        Make-TestObject `
		 | write-fluentd -Server 'http://ls6:9880/' `
		                 -tag 'influxdb.test4' `
		                 -Strings ('Name') `
		                 -Time "MesuerdTime" `
         | Should Be $true
    }
}
