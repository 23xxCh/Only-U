Describe 'BeforeAll Pester compatibility' {
    BeforeAll {
        $expected = 'visible'
        function Get-ExpectedValue { return $expected }

        if ((Get-Module Pester).Version.Major -ge 5) {
            $nativeShould = (Get-Command Should -CommandType Function).ScriptBlock
            function Should {
                param(
                    [Parameter(ValueFromPipeline = $true)]$ActualValue,
                    [Parameter(Position = 0)]$Operator,
                    [Parameter(Position = 1)]$ExpectedValue,
                    [Parameter(Position = 2)]$NotExpectedValue
                )
                process {
                    switch ($Operator) {
                        'Be' { $ActualValue | & $nativeShould -Be $ExpectedValue }
                        'Not' {
                            switch ($ExpectedValue) {
                                'Be' { $ActualValue | & $nativeShould -Not -Be $NotExpectedValue }
                                default { throw "unsupported negative assertion: $ExpectedValue" }
                            }
                        }
                        default { throw "unsupported assertion: $Operator" }
                    }
                }
            }
        }
    }

    It 'shares a setup function and legacy assertion syntax' {
        Get-ExpectedValue | Should Be 'visible'
        'visible' | Should Not Be 'hidden'
    }
}
