Describe 'legacy Pester 3 assertion compatibility' {
    BeforeAll {
        $pesterVersion = (Get-Module Pester).Version
        if ($pesterVersion.Major -ge 5) {
            $script:NativeShould = (Get-Command Should -CommandType Function).ScriptBlock
            function Should {
                [CmdletBinding()]
                param(
                    [Parameter(ValueFromPipeline = $true)] $ActualValue,
                    [Parameter(Position = 0)] [string] $Operator,
                    [Parameter(Position = 1)] $ExpectedValue,
                    [Parameter(Position = 2)] $AdditionalValue
                )
                process {
                    $nativeParameters = @()
                    if ($Operator -eq 'Not') {
                        $nativeParameters += '-Not'
                        $nativeParameters += "-$ExpectedValue"
                        $nativeParameters += $AdditionalValue
                    } else {
                        $nativeParameters += "-$Operator"
                        $nativeParameters += $ExpectedValue
                    }
                    $ActualValue | & $script:NativeShould @nativeParameters
                }
            }
        }
    }

    It 'supports the inherited forms' {
        'a' | Should Be 'a'
        'alphabet' | Should BeLike 'alpha*'
        2 | Should BeGreaterThan 1
        2 | Should BeLessThan 3
        'a' | Should Not Be 'b'
        'a' | Should Not BeLike 'b*'
    }
}
