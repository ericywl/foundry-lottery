## Proveably Random Raffle Contract

**This code is to create a proveably random smart contract lottery.**

### What we want it to do?

1. Users can enter by paying for a ticket.
   - The ticket fees are going to go to the winner during the draw.
2. After X period of time, the lottery will automatically draw a winner.
   - This will be done programatically, using Chainlink VRF & Chainlink Automation
     - Chainlink VRF -> Randomness
     - Chainlink Automation -> Time based trigger
