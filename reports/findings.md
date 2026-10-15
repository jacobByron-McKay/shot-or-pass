# Findings

The tournament gives 1566 shots across 64 matches, excluding penalties. Every one
carries a freeze frame, so for each shot we know where the players the camera
could see were standing. On average a shooter had 2.26 teammates ahead of them.

## A shot model that uses the freeze frames

Distance, goalmouth angle and the number of defenders standing inside the
shooting cone. The third term is the one the positional data buys, and it earns
its place: it is significant at p = 0.0013, and dropping it costs likelihood. The
model is calibrated, predicting a mean scoring rate equal to the observed rate
of 0.0837, and it correlates 0.72 with the xG StatsBomb ship with the data.

## The verdict depends on choices nobody writes down

Deciding whether a player should have passed instead of shooting takes four
further decisions: which teammates count as a real option, how likely a pass is
to arrive, whether the receiver is valued with positional context or on distance
alone, and how large an advantage the alternative needs before the shot is
called wrong.

Running all 36 combinations, the share of shots where shooting beat the best
available alternative ranges from 31.7 to 46.3. That is a spread of 14.6 percentage
points, from choices every one of which is defensible.

## The part worth taking away

The decision that moves the answer most is which teammates count as an option,
worth 7.7 points. It is also the one an analyst would settle in a single line of
filtering and never mention again.

The decision that moves it least, at 0.3 points, is whether the receiver is
valued using the positional data at all. That is the choice with a statistically
significant coefficient behind it, and the one most likely to get a paragraph in
a write-up.

The choice you would justify at length barely matters. The choice you would make
without noticing decides the headline.

## Definitional spread against sampling noise

Holding one specification fixed and resampling the shots, the 95 per cent
interval on that share is 4.8 points wide. The spread across specifications is
14.6 points, which is 3.05 times larger. Reporting the confidence interval and not
the specification range describes the smaller of the two sources of error.

This is not a general law. On a simpler question, counting the same tournament,
the two are close to equal. Which is the point: you cannot tell which case you
are in without running it.

## What the camera did not show

The freeze frames only cover what was on screen. The area ahead of the shooter
was in view a median of 69.6 per cent of the time, so roughly 30.4 per cent of the
space they might have played into is missing from the record. Counting available
options from this data means counting the options a broadcast director chose to
frame. That censoring is measurable and it is real. Tested against the verdict
above, it does not move it, which was not the answer expected when the test was
written.

Data: StatsBomb open data, FIFA Women's World Cup 2023.
