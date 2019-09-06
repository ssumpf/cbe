--
-- Copyright (C) 2019 Genode Labs GmbH, Componolit GmbH, secunet AG
--
-- This file is part of the Consistent Block Encrypter project, which is
-- distributed under the terms of the GNU Affero General Public License
-- version 3.
--

pragma Ada_2012;

with CBE.Request;

package body CBE.Crypto
with Spark_Mode
is
	--
	-- Item
	--
	package body Item
	with Spark_Mode
	is
		--
		-- Execute
		--
		procedure Execute(
			Obj : in out Item_Type;
			Key :        Key_Type)
		is
		begin
			case Primitive.Operation(Obj.Prim) is
			when Request.Write =>

				Aes_Cbc_4k.Encrypt(
					Key,
					Aes_Cbc_4k.Block_Number_Type(Primitive.Block_Number(Obj.Prim)),
					Obj.Plain_Data, Obj.Cipher_Data);

				Primitive.Success(Obj.Prim, Request.True);
				Obj.State := Complete;
			when others =>

				Obj.State := Pending;

			end case;
		end Execute;

		--
		-- Mark_Completed_Primitive
		--
		procedure Mark_Completed_Primitive(
			Obj : in out Item_Type;
			Prm :        Primitive.Object_Type;
			Key :        Key_Type)
		is
			use Request;
		begin
			if
				Obj.State /= In_Progress or
				not Primitive.Equal(Obj.Prim, Prm)
			then
				return;
			end if;

			if
				Primitive.Operation(Obj.Prim) = Request.Read and
				Primitive.Success(Prm)        = Request.True
			then
				Aes_Cbc_4k.Decrypt(
					Key,
					Aes_Cbc_4k.Block_Number_Type(Primitive.Block_Number(Obj.Prim)),
					Obj.Cipher_Data, Obj.Plain_Data);
			end if;

			Obj.State := Item.Complete;
			Primitive.Success(Obj.Prim, Primitive.Success(Prm));

		end Mark_Completed_Primitive;

		--
		-- Copy_Completed_Data
		--
		procedure Copy_Completed_Data(
			Obj        : in     Item_Type;
			Prm        :        Primitive.Object_Type;
			Plain_Data : in out Crypto.Plain_Data_Type)
		is
			use Request;
		begin
			if
				Obj.State /= Complete or
				not Primitive.Equal(Obj.Prim, Prm)
			then
				return;
			end if;

			if
				Primitive.Operation(Obj.Prim) = Request.Read and
				Primitive.Success(Prm)        = Request.True
			then
				-- XXX not sure if that works as expected
				Plain_Data := Obj.Plain_Data;
			end if;
			if
				Primitive.Operation(Obj.Prim) = Request.Write and
				Primitive.Success(Prm)        = Request.True
			then
				-- XXX not sure if that works as expected
				Plain_Data := Crypto.Plain_Data_Type(Obj.Cipher_Data);
			end if;

		end Copy_Completed_Data;

		--
		-- Invalid_Object
		--
		function Invalid_Object
		return Item_Type
		is (
			State       => Invalid,
			Prim        => Primitive.Invalid_Object,
			Plain_Data  => (others => 0),
			Cipher_Data => (others => 0));

		--
		-- Submitted_Object
		--
		function Submitted_Object(
			Prm        : Primitive.Object_Type;
			Plain_Dat  : Plain_Data_Type;
			Cipher_Dat : Cipher_Data_Type)
		return Item_Type
		is (
			State       => Submitted,
			Prim        => Prm,
			Plain_Data  => Plain_Dat,
			Cipher_Data => Cipher_Dat);


		--------------------
		-- Read Accessors --
		--------------------

		function Invalid     (Obj : Item_Type) return Boolean               is (Obj.State = Invalid);
		function Pending     (Obj : Item_Type) return Boolean               is (Obj.State = Pending);
		function Submitted   (Obj : Item_Type) return Boolean               is (Obj.State = Submitted);
		function In_Progress (Obj : Item_Type) return Boolean               is (Obj.State = In_Progress);
		function Complete    (Obj : Item_Type) return Boolean               is (Obj.State = Complete);
		function Prim        (Obj : Item_Type) return Primitive.Object_Type is (Obj.Prim);
		function Plain_Data  (Obj : Item_Type) return Plain_Data_Type       is (Obj.Plain_Data);
		function Cipher_Data (Obj : Item_Type) return Cipher_Data_Type      is (Obj.Cipher_Data);


		---------------------
		-- Write Accessors --
		---------------------

		procedure State(Obj : in out Item_Type; Sta : State_Type) is begin Obj.State := Sta; end State;

	end Item;

	--
	-- Initialize_Object
	--
	procedure Initialize_Object(
		Obj : out Object_Type;
		Key :     Key_Type)
	is
	begin
		Obj := (
			Key              => Key,
			Items            => (others => Item.Invalid_Object),
			Execute_Progress => False);
	end Initialize_Object;

	--
	-- Primitive_Acceptable
	--
	function Primitive_Acceptable(Obj : Object_Type)
	return Boolean
	is (for some Itm of Obj.Items => Item.Invalid(Itm));

	--
	-- Submit_Primitive
	--
	procedure Submit_Primitive(
		Obj         : in out Object_Type;
		Prim        :        Primitive.Object_Type;
		Plain_Data  :        Plain_Data_Type;
		Cipher_Data :        Cipher_Data_Type)
	is
		Prim_Buf : constant Primitive.Object_Type := Prim;
	begin

		Items_Loop: for Item_Id in Obj.Items'Range loop

			if Item.Invalid(Obj.Items(Item_Id)) then

				Obj.Items(Item_Id) :=
					Item.Submitted_Object(Prim_Buf, Plain_Data, Cipher_Data);

				exit Items_Loop;

			end if;

		end loop Items_Loop;

	end Submit_Primitive;

	--
	-- Execute
	--
	procedure Execute(Obj : in out Object_Type)
	is
	begin
		Obj.Execute_Progress := False;
		Items_Loop: for Item_Id in Obj.Items'Range loop
			if Item.Submitted(Obj.Items(Item_Id)) then
				Item.Execute(Obj.Items(Item_Id), Obj.Key);
				Obj.Execute_Progress := True;
			end if;
		end loop Items_Loop;
	end Execute;


	--
	-- Peek_Generated_Primitive
	--
	function Peek_Generated_Primitive(Obj : Object_Type)
	return Primitive.Object_Type
	is
	begin
		Items_Loop: for Item_Id in Obj.Items'Range loop
			if Item.Pending(Obj.Items(Item_Id)) then
				return Item.Prim(Obj.Items(Item_Id));
			end if;
		end loop Items_Loop;
		return Primitive.Invalid_Object;
	end Peek_Generated_Primitive;


	--
	-- Drop_Generated_Primitive
	--
	procedure Drop_Generated_Primitive(
		Obj  : in out Object_Type;
		Prim :        Primitive.Object_Type)
	is
	begin
		Items_Loop: for Item_Id in Obj.Items'Range loop
			if Item.Pending(Obj.Items(Item_Id)) then
				Item.State(Obj.Items(Item_Id), Item.In_Progress);
				return;
			end if;
		end loop Items_Loop;
	end Drop_Generated_Primitive;

	--
	-- Peek_Completed_Primitive
	--
	function Peek_Completed_Primitive(Obj : Object_Type)
	return Primitive.Object_Type
	is
	begin
		for Item_Id in Obj.Items'Range loop
			if Item.Complete(Obj.Items(Item_Id)) then
				return Item.Prim(Obj.Items(Item_Id));
			end if;
		end loop;
		return Primitive.Invalid_Object;
	end Peek_Completed_Primitive;

	--
	-- Drop_Completed_Primitive
	--
	procedure Drop_Completed_Primitive(
		Obj  : in out Object_Type;
		Prim :        Primitive.Object_Type)
	is
	begin
		for Item_Id in Obj.Items'Range loop
			if Item.Complete(Obj.Items(Item_Id)) then
				Obj.Items(Item_Id) := Item.Invalid_Object;
				return;
			end if;
		end loop;
	end Drop_Completed_Primitive;

	--
	-- Mark_Completed_Primitive
	--
	procedure Mark_Completed_Primitive(
		Obj  : in out Object_Type;
		Prim :        Primitive.Object_Type)
	is
	begin
		for Item_Id in Obj.Items'Range loop
			Item.Mark_Completed_Primitive(Obj.Items(Item_Id), Prim, Obj.Key);
		end loop;
	end Mark_Completed_Primitive;

	--
	-- Mark_Completed_Primitive
	--
	procedure Copy_Completed_Data(
		Obj        : in out Crypto.Object_Type;
		Prim       :        Primitive.Object_Type;
		Plain_Data : in out Crypto.Plain_Data_Type)
	is
	begin
		for Item_Id in Obj.Items'Range loop
			Item.Copy_Completed_Data(Obj.Items(Item_Id), Prim, Plain_Data);
		end loop;
	end Copy_Completed_Data;

	---------------
	-- Accessors --
	---------------

	function Execute_Progress(Obj : Object_Type) return Boolean is (Obj.Execute_Progress);

end CBE.Crypto;
