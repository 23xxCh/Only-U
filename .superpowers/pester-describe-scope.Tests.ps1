Describe 'Describe scope' {
    $expected = 'visible'
    function Get-ExpectedValue { return $expected }

    It 'shares direct declarations with its It block' {
        Get-ExpectedValue | Should -Be $expected
    }
}
