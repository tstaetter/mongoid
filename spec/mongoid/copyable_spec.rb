# frozen_string_literal: true

require "spec_helper"

require_relative './copyable_spec_models'

describe Mongoid::Copyable do

  [ :clone, :dup ].each do |method|

    describe "##{method}" do

      let(:person) do
        Person.new(
          title: "Sir",
          version: 4,
          created_at: Time.now,
          updated_at: Time.now,
          desc: "description"
        ) do |p|
          p.owner_id = 5
        end
      end

      let!(:address) do
        person.addresses.build(street: "Bond", name: "Bond")
      end

      let!(:name) do
        person.build_name(first_name: "Judy")
      end

      let!(:posts) do
        person.posts.build(title: "testing")
      end

      let!(:game) do
        person.build_game(name: "Tron")
      end

      let!(:name_translations) do
        person.name.translations.build(language: 'en')
      end

      context "when the document has an id field in the database" do

        let!(:band) do
          Band.create!(name: "Tool")
        end

        before do
          Band.collection.find(_id: band.id).update_one("$set" => { "id" => 1234 })
        end

        let!(:cloned) do
          band.reload.send(method)
        end

        it "does not set the id field as the _id" do
          expect(cloned.id).to_not eq(1234)
        end
      end

      context "when a document has fields from a legacy schema" do

        shared_examples 'behaves as expected' do
          let!(:instance) do
            cls.create!(name: "test")
          end

          before do
            legacy_fields = { "this_is_not_a_field" => 1, "this_legacy_field_is_nil" => nil }
            cls.collection.find(_id: instance.id).update_one("$set" => legacy_fields)
          end

          let(:cloned) do
            instance.reload.send(method)
          end

          it "sets the legacy attribute" do
            expect(cloned.attributes['this_is_not_a_field']).to eq(1)
          end

          it "contains legacy attributes that are nil" do
            expect(cloned.attributes.key?('this_legacy_field_is_nil')).to eq(true)
          end

          it "copies the known attributes" do
            expect(cloned.name).to eq('test')
          end

          it 'calls constructor with explicitly declared attributes only' do
            expect(cls).to receive(:new).with('name' => 'test').and_call_original
            cloned
          end
        end

        context 'without Attributes::Dynamic' do
          let(:cls) { CopyableSpec::Reg }

          before do
            cls.should_not include(Mongoid::Attributes::Dynamic)
          end

          include_examples 'behaves as expected'
        end

        context 'with Attributes::Dynamic' do
          let(:cls) { CopyableSpec::Dyn }

          before do
            cls.should include(Mongoid::Attributes::Dynamic)
          end

          include_examples 'behaves as expected'
        end

      end

      context "when using store_as" do

        context "and dynamic attributes are not set" do

          context 'embeds_one' do

            it "clones" do
              t = StoreAsDupTest1.new(:name => "hi")
              t.build_store_as_dup_test2(:name => "there")
              t.save
              copy = t.send(method)
              expect(copy.object_id).not_to eq(t.object_id)
              expect(copy.store_as_dup_test2.name).to eq(t.store_as_dup_test2.name)
            end
          end

          context 'embeds_many' do


            it "clones" do
              t = StoreAsDupTest3.new(:name => "hi")
              t.store_as_dup_test4s << StoreAsDupTest4.new
              t.save
              copy = t.send(method)
              expect(copy.object_id).not_to eq(t.object_id)
              expect(copy.store_as_dup_test4s).not_to be_empty
              expect(copy.store_as_dup_test4s.first.object_id).not_to eq(t.store_as_dup_test4s.first.object_id)
            end
          end
        end
      end

      context 'nested embeds_many' do
        it 'works' do
          a = CopyableSpec::A.new
          a.locations << CopyableSpec::Location.new
          a.locations.first.buildings << CopyableSpec::Building.new
          a.save!

          new_a = a.send(method)

          expect(new_a.locations.length).to be 1
          expect(new_a.locations.first.buildings.length).to be 1
        end
      end

      context "when cloning a document with multiple languages field" do

        before do
          I18n.enforce_available_locales = false
          I18n.locale = 'pt_BR'
          person.desc = "descrição"
          person.addresses.first.name = "descrição"
          person.save
        end

        after do
          I18n.locale = :en
        end

        let!(:from_db) do
          Person.find(person.id)
        end

        let(:copy) do
          from_db.send(method)
        end

        it "sets the pt_BR version" do
          I18n.locale = 'pt_BR'
          expect(copy.desc).to eq("descrição")
        end

        it "sets the english version" do
          I18n.locale = :en
          expect(copy.desc).to eq("description")
        end

        it "sets to nil an nonexistent lang" do
          I18n.locale = :fr
          expect(copy.desc).to be_nil
        end

        it 'sets embedded translations' do
          I18n.locale = 'pt_BR'
          expect(copy.addresses.first.name).to eq("descrição")
        end

        it 'sets embedded english version' do
          I18n.locale = :en
          expect(copy.addresses.first.name).to eq("Bond")
        end
      end

      context "when cloning a document with polymorphic embedded documents with multiple language field" do

        let!(:shipment_address) do
          person.addresses.build({ shipping_name: "Title" }, ShipmentAddress)
        end

        before do
          I18n.enforce_available_locales = false
          I18n.locale = 'pt_BR'
          person.addresses.type(ShipmentAddress).each { |address| address.shipping_name = "Título" }
          person.save!
        end

        after do
          I18n.locale = :en
        end

        let!(:from_db) do
          Person.find(person.id)
        end

        let(:copy) do
          from_db.send(method)
        end

        it 'sets embedded translations' do
          I18n.locale = 'pt_BR'
          copy.addresses.type(ShipmentAddress).each do |address|
            expect(address.shipping_name).to eq("Título")
          end
        end

      end

      context "when cloning a loaded document" do

        before do
          person.save
        end

        let!(:from_db) do
          Person.find(person.id)
        end

        let(:copy) do
          from_db.send(method)
        end

        it "marks the fields as dirty" do
          expect(copy.changes["age"]).to eq([ nil, 100 ])
        end

        it "flags the document as changed" do
          expect(copy).to be_changed
        end

        it "copies protected fields" do
          expect(copy.owner_id).to eq(5)
        end
      end

      context "when the document is new" do

        context "when there are changes" do

          let(:copy) do
            person.send(method)
          end

          before do
            person[:versions] = [ { number: 1 } ]
          end

          it "returns a new document" do
            expect(copy).to_not be_persisted
          end

          it "has an id" do
            expect(copy.id).to_not be_nil
          end

          it "flags the document as changed" do
            expect(copy).to be_changed
          end

          it "marks fields as dirty" do
            expect(copy.changes["age"]).to eq([ nil, 100 ])
          end

          it "has a different id from the original" do
            expect(copy.id).to_not eq(person.id)
          end

          it "returns a new instance" do
            expect(copy).to_not be_eql(person)
          end

          it "copys embeds many documents" do
            expect(copy.addresses).to eq(person.addresses)
          end

          it "copys deep embeds many documents" do
            expect(copy.name.translations).to eq(person.name.translations)
          end

          it "sets the embedded many documents as new" do
            expect(copy.addresses.first).to be_new_record
          end

          it "sets the deep embedded many documents as new" do
            expect(copy.name.translations.first).to be_new_record
          end

          it "creates new embeds many instances" do
            expect(copy.addresses).to_not equal(person.addresses)
          end

          it "creates new deep embeds many instances" do
            expect(copy.name.translations).to_not equal(person.name.translations)
          end

          it "copys embeds one documents" do
            expect(copy.name).to eq(person.name)
          end

          it "flags the embeds one documents as new" do
            expect(copy.name).to be_new_record
          end

          it "creates a new embeds one instance" do
            expect(copy.name).to_not equal(person.name)
          end

          it "does not copy referenced many documents" do
            expect(copy.posts).to be_empty
          end

          it "does not copy references one documents" do
            expect(copy.game).to be_nil
          end

          it "copies localized fields" do
            expect(copy.desc).to eq("description")
          end

          context "when saving the copy" do

            let(:reloaded) do
              copy.reload
            end

            before do
              copy.save(validate: false)
            end

            it "persists the attributes" do
              expect(reloaded.title).to eq("Sir")
            end

            it "persists the embeds many relation" do
              expect(reloaded.addresses).to eq(person.addresses)
            end

            it "persists the embeds one relation" do
              expect(reloaded.name).to eq(person.name)
            end
          end
        end

        context "when using a custom discriminator_key" do
          before do
            Person.discriminator_key = "dkey"
          end

          after do
            Person.discriminator_key = nil
          end

          let(:copy) do
            person.send(method)
          end

          before do
            person[:versions] = [ { number: 1 } ]
          end

          it "copys embeds many documents" do
            expect(copy.addresses).to eq(person.addresses)
          end

          it "copys deep embeds many documents" do
            expect(copy.name.translations).to eq(person.name.translations)
          end

          it "sets the embedded many documents as new" do
            expect(copy.addresses.first).to be_new_record
          end

          it "sets the deep embedded many documents as new" do
            expect(copy.name.translations.first).to be_new_record
          end

          it "creates new embeds many instances" do
            expect(copy.addresses).to_not equal(person.addresses)
          end

          it "creates new deep embeds many instances" do
            expect(copy.name.translations).to_not equal(person.name.translations)
          end

          it "copys embeds one documents" do
            expect(copy.name).to eq(person.name)
          end

          it "flags the embeds one documents as new" do
            expect(copy.name).to be_new_record
          end

          it "creates a new embeds one instance" do
            expect(copy.name).to_not equal(person.name)
          end

          context "when saving the copy" do

            let(:reloaded) do
              copy.reload
            end

            before do
              copy.save(validate: false)
            end

            it "persists the attributes" do
              expect(reloaded.title).to eq("Sir")
            end

            it "persists the embeds many relation" do
              expect(reloaded.addresses).to eq(person.addresses)
            end

            it "persists the embeds one relation" do
              expect(reloaded.name).to eq(person.name)
            end
          end
        end
      end

      context "when the document is not new" do

        before do
          person.new_record = false
        end

        context "when there are changes" do

          let(:copy) do
            person.send(method)
          end

          before do
            person[:versions] = [ { number: 1 } ]
          end

          it "flags the document as changed" do
            expect(copy).to be_changed
          end

          it "marks fields as dirty" do
            expect(copy.changes["age"]).to eq([ nil, 100 ])
          end

          it "returns a new document" do
            expect(copy).to_not be_persisted
          end

          it "has an id" do
            expect(copy.id).to_not be_nil
          end

          it "has a different id from the original" do
            expect(copy.id).to_not eq(person.id)
          end

          it "returns a new instance" do
            expect(copy).to_not be_eql(person)
          end

          it "copys embeds many documents" do
            expect(copy.addresses).to eq(person.addresses)
          end

          it "creates new embeds many instances" do
            expect(copy.addresses).to_not equal(person.addresses)
          end

          it "copys embeds one documents" do
            expect(copy.name).to eq(person.name)
          end

          it "creates a new embeds one instance" do
            expect(copy.name).to_not equal(person.name)
          end

          it "does not copy referenced many documents" do
            expect(copy.posts).to be_empty
          end

          it "does not copy references one documents" do
            expect(copy.game).to be_nil
          end

          context "when saving the copy" do

            let(:reloaded) do
              copy.reload
            end

            before do
              copy.save(validate: false)
            end

            it "persists the attributes" do
              expect(reloaded.title).to eq("Sir")
            end

            it "persists the embeds many relation" do
              expect(reloaded.addresses).to eq(person.addresses)
            end

            it "persists the embeds one relation" do
              expect(reloaded.name).to eq(person.name)
            end
          end
        end
      end

      context "when the document is frozen" do

        let!(:copy) do
          person.freeze.send(method)
        end

        it "returns a new document" do
          expect(copy).to_not be_persisted
        end

        it "has an id" do
          expect(copy.id).to_not be_nil
        end

        it "has a different id from the original" do
          expect(copy.id).to_not eq(person.id)
        end

        it "returns a new instance" do
          expect(copy).to_not be_eql(person)
        end

        it "copys embeds many documents" do
          expect(copy.addresses).to eq(person.addresses)
        end

        it "creates new embeds many instances" do
          expect(copy.addresses).to_not equal(person.addresses)
        end

        it "copys embeds one documents" do
          expect(copy.name).to eq(person.name)
        end

        it "creates a new embeds one instance" do
          expect(copy.name).to_not equal(person.name)
        end

        it "does not copy referenced many documents" do
          expect(copy.posts).to be_empty
        end

        it "does not copy references one documents" do
          expect(copy.game).to be_nil
        end

        it "keeps the original attributes frozen" do
          expect(person.attributes).to be_frozen
        end

        context "when saving the copy" do

          let(:reloaded) do
            copy.reload
          end

          before do
            copy.save(validate: false)
          end

          it "persists the attributes" do
            expect(reloaded.title).to eq("Sir")
          end

          it "persists the embeds many relation" do
            expect(reloaded.addresses).to eq(person.addresses)
          end

          it "persists the embeds one relation" do
            expect(reloaded.name).to eq(person.name)
          end
        end
      end

      context "when cloning a document with an embedded child class and a custom discriminator value" do

        before do
          ShipmentAddress.discriminator_value = "dvalue"
        end

        after do
          ShipmentAddress.discriminator_value = nil
        end

        let!(:shipment_address) do
          person.addresses.build({}, ShipmentAddress)
        end

        before do
          person.save
        end

        let!(:from_db) do
          Person.find(person.id)
        end

        let(:copy) do
          from_db.send(method)
        end

        it "copys embeds many documents" do
          expect(copy.addresses).to eq(person.addresses)
        end
      end

      context 'when cloning a document with embedded child that uses inheritance' do
        let(:original) do
          CopyableSpec::A.new(influencers: [child_cls.new])
        end

        let(:copy) do
          original.send(method)
        end

        context 'embedded child is root of hierarchy' do
          let(:child_cls) do
            CopyableSpec::Influencer
          end

          before do
            # When embedded class is the root in hierarchy, their
            # discriminator value is not explicitly stored.
            child_cls.discriminator_mapping[child_cls.name].should be nil
          end

          it 'works' do
            copy.class.should be original.class
            copy.object_id.should_not == original.object_id
          end
        end

        context 'embedded child is leaf of hierarchy' do
          let(:child_cls) do
            CopyableSpec::Youtuber
          end

          before do
            # When embedded class is a leaf in hierarchy, their
            # discriminator value is explicitly stored.
            child_cls.discriminator_mapping[child_cls.name].should_not be nil
          end

          it 'works' do
            copy.class.should be original.class
            copy.object_id.should_not == original.object_id
          end
        end
      end
    end
  end
end
