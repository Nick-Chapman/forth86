.." Loading my-letter.f" cr

( Large letter F )

: star      [char] * emit ;
: stars     dup if star 1 - br stars then drop ;
: margin    cr 30 spaces ;
: blip      margin star ;
: bar       margin 5 stars ;
: F         bar blip bar blip blip cr ;
