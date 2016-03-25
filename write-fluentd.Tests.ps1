
## Pester >>
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
. "$here\$sut"
## << Paster



# スクリプト本体の読み込み
. ("{0}\write-fluentd.ps1" -f (Split-Path $MyInvocation.MyCommand.Path -Parent))

# テスト用fluentdサーバー
$TestServerUri = 'http://ls6:9880/'

# テスト・オブジェクト生成 function定義
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



Describe "function Invoke-HttpPost" {
    It "jsonが、ASCIIのみ" {
        Invoke-HttpPost`
          -URI ("{0}/debug" -f $TestServerUri) `
          -Body 'json={"InsideTemp":11.9,"time":"2001-01-01T01:01:01.0000000","Name":"temperature","OutsideTemp":7}' `
        | Should Be $true
    }

    It "json valueが、ASCII文字以外" {
        Invoke-HttpPost `
          -URI ("{0}/debug" -f $TestServerUri) `
          -Body 'json={"InsideTemp":11.9,"time":"2001-01-01T01:01:01.0000000","Name":"温度","OutsideTemp":7}' `
        | Should Be $true
    }

    It "json keyが、ASCII文字以外" {
        Invoke-HttpPost `
          -URI ("{0}/debug" -f $TestServerUri) `
          -Body 'json={"屋内温度":11.9,"time":"2001-01-01T01:01:01.0000000","名称":"temperature","屋外温度":7}' `
        | Should Be $true
    }

}



Describe "function write-influx" {
    It "no data" {
       "" `
         | write-fluentd -Server $TestServerUri `
                         -tag 'debug' `
                         -Strings ('Name') `
                         -Time "MesuerdTime" `
         | Should Be "There is no piped object."
    }

    It "miss match data" {
           write-fluentd -Server $TestServerUri `
                         -tag 'debug' `
                         -Strings ('Name') `
                         -Time "MesuerdTime" `
                         -Data (Make-TestObject) `
         | Should Be "It is not an Object. (Objects array)"
    }
}


Describe "Influxdb" {
    It "post test" {
        Make-TestObject `
         | write-fluentd -Server $TestServerUri `
                         -tag 'influxdb.test4' `
                         -Strings ('Name') `
                         -Time "MesuerdTime" `
         | Should Be $true
    }
}
