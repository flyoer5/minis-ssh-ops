package risk

func rank(level Level) int {
	switch level {
	case Read:
		return 0
	case Write:
		return 1
	case Destructive:
		return 2
	case Blocked:
		return 3
	default:
		return -1
	}
}

func Max(a, b Level) Level {
	if rank(b) > rank(a) {
		return b
	}
	return a
}

func NeedsConfirm(level Level) bool {
	return level == Write || level == Destructive
}
