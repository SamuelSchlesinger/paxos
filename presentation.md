# Distributed Consensus

We work in a setting where there are a number of distributed agents, each being
able to communicate with one another via some unspecified but arbitrarily
unreliable message passing mechanism. Tolerance of this unreliability is often
called fault-tolerance.  The problem of consensus is one of getting all of
these agents to agree on a single value when some subset of them have a
potential proposed value.

Thankfully, this problem is easier than political consensus, as these agents don't
care which value they choose.

---

# Requirements for Consensus

A consensus algorithm will tell us how to operate a number of agents to reach
consensus on some value. The following are requirements we're going to
use to refine this further:

## Safety (also called agreement/consistency)

The algorithm should not choose multiple values.

## Validity (also called non-triviality)

The value chosen should be one of the ones proposed by the agents.

## Termination (also called liveness)

If a value has been chosen, then, under good network conditions, all agents
will know the chosen value eventually.

---

# Impossibility Result

You may have noticed that, for termination, we only require that it works under
good (left unspecified) network conditions. The reason that this is acceptable
to us is due to work by Fischer, Lynch, and Paterson (FLP) showing that,
under arbitrary network conditions, it is impossible to reliably come to
consensus.

Thus, algorithms which claim to tackle this problem must accept that their
approach will not work in all circumstances. With the specification we've
given, algorithms must accept that their approach will prioritize safety over
termination.

---

# Paxos

The Paxos algorithm was invented by Leslie Lamport to solve this problem.
Originally, the algorithm had three different types of agent, but we'll
consider only one here.

The algorithm takes place in a series of round, each of which works in two
phases. In phase 1, an agent holds an election for itself to become leader. In
the second, that leader conducts an election for the value, carefully selecting
which to propose in order to not violate safety. The rounds are numbered
uniquely in such a way that two processes will never use the same round number,
perhaps by giving each process a number and choosing round numbers for each
like:

```
i, i + n, i + 2n
```

Here, `n` is the number of agents, and each agent will be given an `i` from `0` to `n - 1`.

---

# Paxos Phase 1

Each phase is broken up into the communication from the leader or candidate and
the communication back from the agents. These will be referred to as phase 1a
and 1b in the literature.

In 1a, the candidate for leader sends out a message with a unique round number
to the other processes asking them to elect them leader for this round.

In 1b, the agents receiving the message check if they've seen any message with
a higher round number.  If they have, they'll simply ignore the message.
Otherwise, their response will depend on if they've previously accepted a
value. If they have, they'll send it back, along with the term in which they
accepted it. Either way, they'll send back an indication confirming their vote
for the leader.

```
(1a) candidate          (1b) candidate
         |                       ^
         | hey!                  | sure! I voted for "Universal Healthcare" in
         | elect me in 2024      | round 2020 in case you want to propose that
         v                       |
       agents                  agents 
```

---

# Paxos Phase 2 1a

In the second phase, the leader needs to choose what value to propose to the
other agents. The rest of the agents don't want to think about what to vote
for, or else why would they elect a leader? Thus, the leader better make sure
that it does not violate the safety requirement of consensus. This comprises
phase 2a of the algorithm.

In order to do this, it suffices to ensure that, if there were any value chosen
in a previous round, we will propose it in this round. If a value were chosen
in any such round, it would have been sent to us in the majority of responses
we got back, as any two majorities overlap, and a value can only be chosen by a
majority.  If a value were chosen, however, we don't know which round it was
in. We split up our analysis into three possible cases.

1. In the most recent round in which an agent has accepted a value, that value
   was chosen.
2. In some other round, there was a value accepted.
3. No value was ever accepted.

---

# Paxos Phase 2 1a (cont.)

Recall:

1. In the most recent round in which an agent has accepted a value, that value
   was chosen.
2. In some other round, there was a value accepted.
3. No value was ever accepted.

In case 1, we definitely want to choose the value which was accepted in the
most recent round, as it which we know from that agent. In case 2, the leader
of the most recent round for which we have an accepted value would have also
noticed the previously accepted value (by induction), so it suffices to take
the value from the most recent acceptance every time. In case 3, no value was
ever accepted, so we use the value the leader meant to propose in the first
place.

---

# Paxos Phase 2 1b

After selecting this value, the leader sends it to the agents and waits for a
majority of responses. Phase 2b is simply the agents accepting the value if
they haven't already received a message with a higher round number and thus
entered into a new election.

```
  (1a) leader                             leader
         |                                  ^
         | hey!                             | anything for you, Generalissimo
         | vote for "Universal Healthcare"  |
         |                                  |
         v                                  |
       agents                             agents
```

After phase 2b succcessfully completes, we know that no other value will ever
be chosen, as any round which takes place will select this value via the
mechanism we described in 2a.

---

# Conclusion

The Paxos algorithm works by a number of agents repeatedly attempting to become
leader of a very peculiar election and trying to ram their legislation through
before the other agents decide they'd like to take over because they think their
leader is dead due to of bad internet connection.

The single value consensus algorithm I described here today can be knit
together into an algorithm for consensus over a sequence of values, and using
that into a framework for replicated state machines, one of the important
techniques used for designing fault tolerant systems today.
