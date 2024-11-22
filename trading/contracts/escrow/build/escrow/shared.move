// Creating shared object for escrow module
module escrow::shared {
		// Importing the sui module
		use sui::{
				event,
				dynamic_object_field::{Self as dof}
		};

		// Importing the lock module
		use escrow::lock::{Locked, Key};

		public struct EscrowedObjectKey has copy, store, drop {}

		// Escrow is a generic struct that holds the escrowed object, the sender, the recipient, and the exchange key
		// Defining a new type(T) to hold the escrowed object
		public struct Escrow<phantom T: key + store> has key, store {
				// Adding properties to the Escrow object struct
				id: UID,
				sender: address,
				recipient: address,
				exchange_key: ID,
		}

		// Error code for mismatched sender and recipient
		const EMismatchedSenderRecipient: u64 = 0;
		// Error code for mismatched exchange object
		const EMismatchedExchangeObject: u64 = 1;

		// Create function to create an escrow object
		public fun create<T: key + store>(
				// Defining the properties of the escrowed object
				escrowed: T,
				exchange_key: ID,
				recipient: address,
				ctx: &mut TxContext
		) {
				// Creating a new escrow object
				let mut escrow = Escrow<T> {
						id: object::new(ctx),
						sender: ctx.sender(),
						recipient,
						exchange_key,
				};
				// Emitting an event for the creation of the escrow object
				event::emit(EscrowCreated {
						// Adding the properties of the escrow object to the event
						escrow_id: object::id(&escrow),
						key_id: exchange_key,
						sender: escrow.sender,
						recipient,
						item_id: object::id(&escrowed),
				});

				// Adding the escrowed object to the escrow object
				dof::add(&mut escrow.id, EscrowedObjectKey {}, escrowed);

				// Sharing the escrow object
				transfer::public_share_object(escrow);
		}

		// Swap function to swap the escrowed object
		public fun swap<T: key + store, U: key + store>(
				mut escrow: Escrow<T>,
				key: Key,
				locked: Locked<U>,
				ctx: &TxContext,
		): T {
				let escrowed = dof::remove<EscrowedObjectKey, T>(&mut escrow.id, EscrowedObjectKey {});

				let Escrow {
						id,
						sender,
						recipient,
						exchange_key,
				} = escrow;

				// Check if the sender, recipient, and exchange key match the escrow object
				assert!(recipient == ctx.sender(), EMismatchedSenderRecipient);
				assert!(exchange_key == object::id(&key), EMismatchedExchangeObject);

				// Unlock the escrowed object
				transfer::public_transfer(locked.unlock(key), sender);

				// Emit an event for the swapping of the escrow object
				event::emit(EscrowSwapped {
						// Adding the escrow id to the event
						escrow_id: id.to_inner(),
				});

				// Delete the escrow object
				id.delete();

				// Return the escrowed object
				escrowed
		}

		// Return to sender function to return the escrowed object to the sender
		// The escrow object is deleted after the object is returned to the sender
		public fun return_to_sender<T: key + store>(
				// Defining the properties of the escrow object
				mut escrow: Escrow<T>,
				ctx: &TxContext
		): T {
				// Removing the escrowed object from the escrow object
				event::emit(EscrowCancelled {
						// Adding the escrow id to the event
						escrow_id: object::id(&escrow)
				});

				// Removing the escrowed object from the escrow object
				let escrowed = dof::remove<EscrowedObjectKey, T>(&mut escrow.id, EscrowedObjectKey {});

				// Destructuring the escrow object
				let Escrow {
						// Extracting the properties of the escrow object
						id,
						sender,
						recipient: _,
						exchange_key: _,
				} = escrow;

				// Transfer the escrowed object back to the sender
				assert!(sender == ctx.sender(), EMismatchedSenderRecipient);
				// Delete the escrow object
				id.delete();
				// Return the escrowed object
				escrowed
		}

		// Event for the creation of an escrow object
		// The event contains the escrow id, the key id, the sender, the recipient, and the item id
		public struct EscrowCreated has copy, drop {
				escrow_id: ID,
				key_id: ID,
				sender: address,
				recipient: address,
				item_id: ID,
		}

		// Event for the swapping of an escrow object
		public struct EscrowSwapped has copy, drop {
				escrow_id: ID
		}

		// Event for the cancellation of an escrow object
		public struct EscrowCancelled has copy, drop {
				escrow_id: ID
		}

		#[test_only] use sui::coin::{Self, Coin};
		#[test_only] use sui::sui::SUI;
		#[test_only] use sui::test_scenario::{Self as ts, Scenario};

		#[test_only] use escrow::lock;

		#[test_only] const ALICE: address = @0xA;
		#[test_only] const BOB: address = @0xB;
		#[test_only] const DIANE: address = @0xD;

		// Test function to create a coin for testing
		#[test_only]
		fun test_coin(ts: &mut Scenario): Coin<SUI> {
				coin::mint_for_testing<SUI>(42, ts.ctx())
		}

		// Test function to test the creation of an escrow object
		#[test]
		fun test_successful_swap() {
				// Creating a new test scenario
				let mut ts = ts::begin(@0x0);

				// Coin created by Bob & locked
				let (i2, ik2) = {
						ts.next_tx(BOB);
						let c = test_coin(&mut ts);
						let cid = object::id(&c);
						let (l, k) = lock::lock(c, ts.ctx());
						let kid = object::id(&k);
						transfer::public_transfer(l, BOB);
						transfer::public_transfer(k, BOB);
						(cid, kid)
				};

				// Coin created by Alice & escrowed
				let i1 = {
						ts.next_tx(ALICE);
						let c = test_coin(&mut ts);
						let cid = object::id(&c);
						// Creating the escrow object
						create(c, ik2, BOB, ts.ctx());
						// Returning the coin id
						cid
				};

				{
						ts.next_tx(BOB);
						let escrow: Escrow<Coin<SUI>> = ts.take_shared();
						let k2: Key = ts.take_from_sender();
						let l2: Locked<Coin<SUI>> = ts.take_from_sender();
						let c = escrow.swap(k2, l2, ts.ctx());

						transfer::public_transfer(c, BOB);
				};
				ts.next_tx(@0x0);

				{
						let c: Coin<SUI> = ts.take_from_address_by_id(ALICE, i2);
						ts::return_to_address(ALICE, c);
				};

				{
						let c: Coin<SUI> = ts.take_from_address_by_id(BOB, i1);
						ts::return_to_address(BOB, c);
				};

				ts::end(ts);
		}

		#[test]
		#[expected_failure(abort_code = EMismatchedSenderRecipient)]
		fun test_mismatch_sender() {
				let mut ts = ts::begin(@0x0);

				let ik2 = {
						ts.next_tx(DIANE);
						let c = test_coin(&mut ts);
						let (l, k) = lock::lock(c, ts.ctx());
						let kid = object::id(&k);
						transfer::public_transfer(l, DIANE);
						transfer::public_transfer(k, DIANE);
						kid
				};

				{
						ts.next_tx(ALICE);
						let c = test_coin(&mut ts);
						create(c, ik2, BOB, ts.ctx());
				};

				{
						ts.next_tx(DIANE);
						let escrow: Escrow<Coin<SUI>> = ts.take_shared();
						let k2: Key = ts.take_from_sender();
						let l2: Locked<Coin<SUI>> = ts.take_from_sender();
						let c = escrow.swap(k2, l2, ts.ctx());

						transfer::public_transfer(c, DIANE);
				};

				abort 1337
		}

		#[test]
		#[expected_failure(abort_code = EMismatchedExchangeObject)]
		fun test_mismatch_object() {
				let mut ts = ts::begin(@0x0);

				{
						ts.next_tx(BOB);
						let c = test_coin(&mut ts);
						let (l, k) = lock::lock(c, ts.ctx());
						transfer::public_transfer(l, BOB);
						transfer::public_transfer(k, BOB);
				};

				{
						ts.next_tx(ALICE);
						let c = test_coin(&mut ts);
						let cid = object::id(&c);
						create(c, cid, BOB, ts.ctx());
				};

				{
						ts.next_tx(BOB);
						let escrow: Escrow<Coin<SUI>> = ts.take_shared();
						let k2: Key = ts.take_from_sender();
						let l2: Locked<Coin<SUI>> = ts.take_from_sender();
						let c = escrow.swap(k2, l2, ts.ctx());

						transfer::public_transfer(c, BOB);
				};

				abort 1337
		}

		#[test]
		#[expected_failure(abort_code = EMismatchedExchangeObject)]
		fun test_object_tamper() {
				let mut ts = ts::begin(@0x0);

				let ik2 = {
						ts.next_tx(BOB);
						let c = test_coin(&mut ts);
						let (l, k) = lock::lock(c, ts.ctx());
						let kid = object::id(&k);
						transfer::public_transfer(l, BOB);
						transfer::public_transfer(k, BOB);
						kid
				};

				{
						ts.next_tx(ALICE);
						let c = test_coin(&mut ts);
						create(c, ik2, BOB, ts.ctx());
				};

				{
						ts.next_tx(BOB);
						let k: Key = ts.take_from_sender();
						let l: Locked<Coin<SUI>> = ts.take_from_sender();
						let mut c = lock::unlock(l, k);

						let _dust = c.split(1, ts.ctx());
						let (l, k) = lock::lock(c, ts.ctx());
						let escrow: Escrow<Coin<SUI>> = ts.take_shared();
						let c = escrow.swap(k, l, ts.ctx());

						transfer::public_transfer(c, BOB);
				};

				abort 1337
		}

		#[test]
		fun test_return_to_sender() {
				let mut ts = ts::begin(@0x0);

				let cid = {
						ts.next_tx(ALICE);
						let c = test_coin(&mut ts);
						let cid = object::id(&c);
						let i = object::id_from_address(@0x0);
						create(c, i, BOB, ts.ctx());
						cid
				};

				{
						ts.next_tx(ALICE);
						let escrow: Escrow<Coin<SUI>> = ts.take_shared();
						let c = escrow.return_to_sender(ts.ctx());

						transfer::public_transfer(c, ALICE);
				};

				ts.next_tx(@0x0);

				{
						let c: Coin<SUI> = ts.take_from_address_by_id(ALICE, cid);
						ts::return_to_address(ALICE, c)
				};

				ts::end(ts);
		}

		#[test]
		#[expected_failure]
		fun test_return_to_sender_failed_swap() {
				let mut ts = ts::begin(@0x0);

				let ik2 = {
						ts.next_tx(BOB);
						let c = test_coin(&mut ts);
						let (l, k) = lock::lock(c, ts.ctx());
						let kid = object::id(&k);
						transfer::public_transfer(l, BOB);
						transfer::public_transfer(k, BOB);
						kid
				};

				{
						ts.next_tx(ALICE);
						let c = test_coin(&mut ts);
						create(c, ik2, BOB, ts.ctx());
				};

				{
						ts.next_tx(ALICE);
						let escrow: Escrow<Coin<SUI>> = ts.take_shared();
						let c = escrow.return_to_sender(ts.ctx());
						transfer::public_transfer(c, ALICE);
				};

				{
						ts.next_tx(BOB);
						let escrow: Escrow<Coin<SUI>> = ts.take_shared();
						let k2: Key = ts.take_from_sender();
						let l2: Locked<Coin<SUI>> = ts.take_from_sender();
						let c = escrow.swap(k2, l2, ts.ctx());

						transfer::public_transfer(c, BOB);
				};

				abort 1337
		}
}
