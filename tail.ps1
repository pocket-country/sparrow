# playing around with -regex and switch.
# This is a 'pre-parser'; seeing how this technique might work.
# Got it to handle multi line comments, still needs a little tweaking
# But - deal breaker - won't handle nested comments.  This is a limit 
# of RegEx.
# So, moving on.
# See "minnow.ps1" for DFA that will handle nested comments

$src = Get-Content "TestComments.txt" -raw;

# working copy of input
$tail = $src;
$charsLeft = $tail.Length;
Write-Output "Starting with text of length $charsLeft characters.";

#collect non-comment strings
$outTxt = New-Object -TypeName "System.Collections.ArrayList";
#collect comment strings
$commentList = New-Object -TypeName "System.Collections.ArrayList";

$iter = 0;
while (<#$iter -lt 7#>$charsLeft -Gt 0) {
    Write-Output "Iteration ($iter)"
    switch ($tail) {
        {$script:r = [regex]::match($_,'/\*(.|\n)*?\*/'); return $r.success;}
            { 
                #$r = $script:r; # to shorten notation
                # !watch scope on these
                Write-Output "-> Block comment matched!";
                #Write-Output $r.success;
                #Write-Output $r.index $r.length;
                #Write-Output $r.value;

                # might have match at beginning of string
                if ($r.index -gt 0) {
                    $head = $_.substring(0, $r.index);
                    [void] $outTxt.add($head);
                }
                [void] $commentList.add($r.value);
                Break; 
            }
            {$script:r = [regex]::match($_,'--.*?\n'); return $r.success;}
            { 
                #Write-Output $r.success;
                #Write-Output $r.index $r.length;
                #Write-Output $r.value | Format-Hex;
                 if ($r.index -gt 0 ) { 
                    $head = $_.substring(0, $r.index);
                    [void] $outTxt.add($head);
                }
                [void] $commentList.add($r.value);
                Write-Output "-> Line comment matched!";
                Break; 
            }

        default { #if we didn't match anything, last bit left, add it to output chunks 
            $outTxt.add($tail);
            $tail = "";
            Write-Output "-> Fell through to default."  }
    }
    # this could be wrapped up in  a functon?
    <#Write-Output "-> After switch with: ";
    Write-Output $r.success;
    Write-Output $r.index;
    Write-Output $r.length;
    Write-Output $r.value;
    #>
    # capture everything after the matched portion of input & loop, baby, loop
    if ($script:r.success) {$tail = $tail.substring($script:r.index + $script:r.length);}
    $charsLeft = $tail.Length;
    $iter++; 
 
    Write-Output "At end of $iter Left with $charsLeft characters";
}
# done with processing loop.  Let's dump saved chunks and see what we've got
Write-Output "Done with processing loop"
Write-Output "Text collected:";
ForEach ($chunk in $outTxt) {Write-Output $chunk <#| Format-Hex#> }
Write-Output "Comments Collected:";
ForEach ($chunk in $commentList) {Write-Output $chunk <#| Format-Hex#> }
