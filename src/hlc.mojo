"""Hybrid logical clock: (wall ms, counter, node id), totally ordered."""


@fieldwise_init
struct HLC(Copyable, Equatable, Writable):
    var wall: Int
    var counter: Int
    var node: String

    def __lt__(self, other: Self) -> Bool:
        if self.wall != other.wall:
            return self.wall < other.wall
        if self.counter != other.counter:
            return self.counter < other.counter
        return self.node < other.node

    def __eq__(self, other: Self) -> Bool:
        return (
            self.wall == other.wall
            and self.counter == other.counter
            and self.node == other.node
        )

    def encode(self) -> String:
        return String(self.wall, ":", self.counter, ":", self.node)

    def write_to(self, mut writer: Some[Writer]):
        writer.write(self.encode())


struct HLCClock(Movable):
    """Per-replica clock. Physical time is passed in so tests are deterministic."""

    var node: String
    var wall: Int
    var counter: Int

    def __init__(out self, node: String):
        self.node = node
        self.wall = 0
        self.counter = 0

    def tick(mut self, phys: Int) -> HLC:
        """Timestamp a local event."""
        var new_wall = max(self.wall, phys)
        if new_wall == self.wall:
            self.counter += 1
        else:
            self.counter = 0
        self.wall = new_wall
        return HLC(self.wall, self.counter, self.node)

    def observe(mut self, remote: HLC, phys: Int) -> HLC:
        """Merge a remote timestamp, returning a stamp ordered after both."""
        var new_wall = max(max(self.wall, remote.wall), phys)
        if new_wall == self.wall and new_wall == remote.wall:
            self.counter = max(self.counter, remote.counter) + 1
        elif new_wall == self.wall:
            self.counter += 1
        elif new_wall == remote.wall:
            self.counter = remote.counter + 1
        else:
            self.counter = 0
        self.wall = new_wall
        return HLC(self.wall, self.counter, self.node)
