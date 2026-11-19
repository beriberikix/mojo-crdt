"""Deterministic in-process network simulator for convergence testing."""

from doc import Doc
from hlc import HLC
from replica import Replica, Batch
from storage import Storage


struct Rng(Movable):
    """xorshift64: seedable and dependency-free."""

    var state: UInt64

    def __init__(out self, seed: Int):
        self.state = UInt64(seed) * 6364136223846793005 + 1442695040888963407

    def next(mut self) -> UInt64:
        var x = self.state
        x ^= x << 13
        x ^= x >> 7
        x ^= x << 17
        self.state = x
        return x

    def below(mut self, n: Int) -> Int:
        return Int(self.next() % UInt64(n))

    def chance(mut self, percent: Int) -> Bool:
        return self.below(100) < percent


@fieldwise_init
struct Delayed(Copyable):
    """A batch delivered late / out of order / again."""

    var target: Int
    var batch: Batch


struct Cluster[S: Storage](Movable):
    var replicas: List[Replica[Self.S]]
    var skew: List[Int]  # per-replica physical clock offset (ms)
    var pull_cp: List[Int]  # [i*n+j]: i's checkpoint into j's seqs
    var push_cp: List[Int]  # [i*n+j]: i's checkpoint of its own seqs sent to j
    var delayed: List[Delayed]
    var page: Int

    def __init__(out self, var replicas: List[Replica[Self.S]], page: Int = 3):
        var n = len(replicas)
        self.replicas = replicas^
        self.skew = List[Int]()
        self.pull_cp = List[Int]()
        self.push_cp = List[Int]()
        for _ in range(n):
            self.skew.append(0)
        for _ in range(n * n):
            self.pull_cp.append(0)
            self.push_cp.append(0)
        self.delayed = List[Delayed]()
        self.page = page

    def n(self) -> Int:
        return len(self.replicas)

    def now(self, i: Int, step: Int) -> Int:
        return 1_000_000 + step * 10 + self.skew[i]

    def write(
        mut self, i: Int, doc_id: String, field: String, value: String, step: Int
    ) raises -> HLC:
        return self.replicas[i].local_write(
            doc_id, field, value, self.now(i, step)
        )

    def sync_pair(
        mut self,
        i: Int,
        j: Int,
        step: Int,
        mut rng: Rng,
        loss: Int,
        dup: Int,
        delay: Int,
    ) raises:
        """One pull (i<-j) and one push (i->j) round over a lossy link.

        A checkpoint only advances on a delivered ack, so losses are retried.
        """
        var n = self.n()
        # ---- pull: i asks j for changes since pull_cp[i][j]
        if not rng.chance(loss):
            var b = self.replicas[j].make_batch(self.pull_cp[i * n + j], self.page)
            if not rng.chance(loss):  # response survives the network
                if rng.chance(delay):
                    self.delayed.append(Delayed(i, b.copy()))
                else:
                    _ = self.replicas[i].apply_batch(b, self.now(i, step))
                    if rng.chance(dup):
                        _ = self.replicas[i].apply_batch(b, self.now(i, step))
                    self.pull_cp[i * n + j] = b.upto
        # ---- push: i sends j changes since push_cp[i][j]
        if not rng.chance(loss):
            var b = self.replicas[i].make_batch(self.push_cp[i * n + j], self.page)
            if rng.chance(delay):
                self.delayed.append(Delayed(j, b.copy()))
            else:
                _ = self.replicas[j].apply_batch(b, self.now(j, step))
                if rng.chance(dup):
                    _ = self.replicas[j].apply_batch(b, self.now(j, step))
                if not rng.chance(loss):  # ack survives
                    self.push_cp[i * n + j] = b.upto

    def deliver_one_delayed(mut self, step: Int, mut rng: Rng) raises:
        """Deliver a random stale in-flight batch (reordering)."""
        if len(self.delayed) == 0:
            return
        var k = rng.below(len(self.delayed))
        var d = self.delayed[k].copy()
        _ = self.delayed.pop(k)
        _ = self.replicas[d.target].apply_batch(d.batch, self.now(d.target, step))

    def settle(mut self, step: Int) raises:
        """Reliable full sync until quiescent (the network heals)."""
        var rng = Rng(1)
        for d in self.delayed.copy():
            _ = self.replicas[d.target].apply_batch(d.batch, self.now(d.target, step))
        self.delayed = List[Delayed]()
        var n = self.n()
        for _ in range(20):
            for i in range(n):
                for j in range(n):
                    if i != j:
                        self.sync_pair(i, j, step, rng, 0, 0, 0)

    def converged(self, ids: List[String]) raises -> Bool:
        for id in ids:
            var first = self.replicas[0].get(id)
            for r in range(1, self.n()):
                var other = self.replicas[r].get(id)
                if Bool(first) != Bool(other):
                    return False
                if first and not first.value().same_state(other.value()):
                    return False
        return True
