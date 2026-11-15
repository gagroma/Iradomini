extends RefCounted

const AUTHOR := "Father Anselm Voss"

const PAGES := [
	["The bells", "The bishop sent me the week the bells fell silent. No one rings them now, yet at night the villagers still hear something in the church. Not bells. Singing, high and wrong, like a choir heard backwards.\n\nI went in at dusk with candle and chalk. The pews are overturned. The altar has been stripped bare."],
	["What walks here", "I have seen it. Tall as a door, bent, with arms that drag on the stone and a broken halo hanging crooked over its head. It does not see well in the dark, but it hears everything: every step, every scrape. When I ran, it came.\n\nWalk softly. Crouch by the pews. Never run unless you must."],
	["The chalk", "Chalk blessed at Easter holds it. A line it will not cross, but only if the line is closed into a ring. An open line is nothing; it burns away.\n\nI drew a ring around myself and it screamed at the edge until it tired. Once I closed a ring around it, and it came apart like ash. It came back later. They always come back."],
	["The gun", "The sexton's sawn-off, both barrels loaded with shot I blessed myself. It will not kill the thing. Nothing made by a gunsmith will.\n\nBut it staggers it. A full charge in the chest and it stood dazed, swaying, deaf and blind to me, long enough to close a ring around it. Each time it wakes sooner, as if it learns.\n\nI lost it somewhere in the side rooms when it came for me, with spare shells scattered after it. Look for them. Break it open and thumb in fresh shells from your pocket. The noise carries through every room. Make each one count."],
	["The four holy things", "Whatever did this took the four holy things from the altar and scattered them through the rooms: the Chalice, the Cross, the Censer and the Book of Prayers.\n\nEach must go back to its own place. The Cross at the back, the Chalice on the left, the Censer on the right, the Book before them. Only then can the rite be read."],
	["The rite", "With all four in place, take up the Book and read the prayer to Saint Michael, every word of it.\n\nIt will know. It will come for you while you read. Do not stop. Do not look away from the page for long. The last word is the one that casts it down.\n\nTwice I hid from it in a vestry wardrobe and it passed me by. But never let it see you climb in."],
	["Before I go in", "Three of them are on the altar now. Only the Book is left, somewhere deep in the side rooms, and I hear it moving between me and it.\n\nThe circle around the altar is not finished and my chalk is almost gone. I leave this journal here by the door with a fresh candle. The gun is still out there, loaded.\n\nWhoever finds it: bring the four home. Read it to the end."],
]


static func numeral(i: int) -> String:
	return ["I", "II", "III", "IV", "V", "VI", "VII", "VIII"][i]
