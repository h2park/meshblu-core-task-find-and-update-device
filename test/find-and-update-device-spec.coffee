_                   = require 'lodash'
mongojs             = require 'mongojs'
moment              = require 'moment'
Datastore           = require 'meshblu-core-datastore'
redis               = require 'fakeredis'
FindAndUpdateDevice = require '../'
JobManager          = require 'meshblu-core-job-manager'
DeviceManager       = require 'meshblu-core-manager-device'
uuid                = require 'uuid'

describe 'FindAndUpdateDevice', ->
  beforeEach (done) ->
    @redisKey = uuid.v1()
    @uuidAliasResolver = resolve: (uuid, callback) => callback(null, uuid)

    @jobManager = new JobManager
      client: _.bindAll redis.createClient @redisKey
      timeoutSeconds: 1
      jobLogSampleRate: 1
    database = mongojs 'meshblu-core-task-find-and-update-device', ['devices']
    @datastore = new Datastore
      database: database
      moment: moment
      collection: 'devices'

    @deviceManager = new DeviceManager {@datastore, @uuidAliasResolver}

    database.devices.remove done

  beforeEach ->
    @sut = new FindAndUpdateDevice {@datastore, @uuidAliasResolver, @jobManager}

  describe '->do', ->
    describe 'when the device does not exist in the datastore', ->
      beforeEach (done) ->
        request =
          metadata:
            responseId: 'used-as-biofuel'
            auth:
              uuid: 'thank-you-for-considering'
              token: 'the-environment'
            toUuid: '2-you-you-eye-dee'
          rawData: '{}'

        @sut.do request, (error, @response) => done error

      it 'should respond with a 404', ->
        expect(@response.metadata.code).to.equal 404

    describe 'when the device does exists in the datastore', ->
      beforeEach (done) ->
        record =
          uuid: '2-you-you-eye-dee'
          token: 'never-gonna-guess-me'
          meshblu:
            tokens:
              'GpJaXFa3XlPf657YgIpc20STnKf2j+DcTA1iRP5JJcg=': {}
        @datastore.insert record, done

      describe 'when called', ->
        beforeEach (done) ->
          request =
            metadata:
              responseId: 'used-as-biofuel'
              auth:
                uuid: 'thank-you-for-considering'
                token: 'the-environment'
              toUuid: '2-you-you-eye-dee'
            rawData: JSON.stringify $set: {sandbag: "this'll hold that pesky tsunami!"}

          @sut.do request, (error, @response) => done error

        it 'should respond with a 200', ->
          expect(@response.metadata.code).to.equal 200

        it 'should return the document', ->
          expected =
            uuid: '2-you-you-eye-dee'
            token: 'never-gonna-guess-me'
            meshblu:
              tokens:
                'GpJaXFa3XlPf657YgIpc20STnKf2j+DcTA1iRP5JJcg=': {}

          expect(@response.data).to.deep.equal expected

        describe 'JobManager gets DeliverConfigMessage job', (done) ->
          beforeEach (done) ->
            @jobManager.getRequest ['request'], (error, @request) =>
              done error

          it 'should be a config messageType', ->
            message =
              uuid:"2-you-you-eye-dee"
              token:"never-gonna-guess-me"
              meshblu:
                tokens:
                  "GpJaXFa3XlPf657YgIpc20STnKf2j+DcTA1iRP5JJcg=":{}
              sandbag:"this'll hold that pesky tsunami!"

            auth =
              uuid: 'thank-you-for-considering'
              token: 'the-environment'

            {rawData, metadata} = @request
            expect(metadata.auth).to.deep.equal uuid: '2-you-you-eye-dee'
            expect(metadata.jobType).to.equal 'DeliverConfigMessage'
            expect(metadata.fromUuid).to.equal '2-you-you-eye-dee'
            expect(metadata.messageType).to.equal 'config'
            expect(metadata.toUuid).to.equal '2-you-you-eye-dee'
            expect(JSON.parse rawData).to.containSubset message

        describe 'JobManager gets DeliverConfigureSent job', (done) ->
          beforeEach 'discard DeliverConfigMessage', (done) ->
            @jobManager.getRequest ['request'], done

          beforeEach (done) ->
            @jobManager.getRequest ['request'], (error, @request) =>
              done error

          it 'should be a config messageType', ->
            expect(@request).to.exist

            message =
              uuid:"2-you-you-eye-dee"
              token:"never-gonna-guess-me"
              meshblu:
                tokens:
                  "GpJaXFa3XlPf657YgIpc20STnKf2j+DcTA1iRP5JJcg=":{}
              sandbag:"this'll hold that pesky tsunami!"

            auth =
              uuid: 'thank-you-for-considering'
              token: 'the-environment'

            {rawData, metadata} = @request
            expect(metadata.auth).to.deep.equal uuid: '2-you-you-eye-dee'
            expect(metadata.jobType).to.equal 'DeliverConfigureSent'
            expect(metadata.fromUuid).to.equal '2-you-you-eye-dee'
            expect(JSON.parse rawData).to.containSubset message

        describe 'when the record is retrieved', ->
          beforeEach (done) ->
            @datastore.findOne {uuid: '2-you-you-eye-dee'}, (error, @record) =>
              done error

          it 'should update the record', ->
            expect(@record).to.containSubset
              sandbag: "this'll hold that pesky tsunami!"

          it 'should update/set the updatedAt time',->
            expect(@record.meshblu.updatedAt).to.exist
            updatedAt = moment(@record.meshblu.updatedAt).valueOf()
            expect(updatedAt).to.be.closeTo moment().valueOf(), 3000

          it 'should store a hash of the device', ->
            expect(@record.meshblu.hash).to.exist

      describe 'when request is for the wrong uuid', ->
        beforeEach (done) ->
          request =
            metadata:
              responseId: 'used-as-biofuel'
              auth:
                uuid: 'thank-you-for-considering'
                token: 'the-environment'
              toUuid: 'skin-falls-off'
            rawData: '{}'

          @sut.do request, (error, @response) => done error

        it 'should respond with a 404', ->
          expect(@response.metadata.code).to.equal 404

      describe 'when request contains invalid JSON', ->
        beforeEach (done) ->
          request =
            metadata:
              responseId: 'used-as-biofuel'
              auth:
                uuid: 'thank-you-for-considering'
                token: 'the-environment'
              toUuid: 'skin-falls-off'
            rawData: 'Ω'

          @sut.do request, (error, @response) => done error

        it 'should respond with a 422', ->
          expect(@response.metadata.code).to.equal 422

      describe 'when request contains $ key', ->
        beforeEach (done) ->
          request =
            metadata:
              responseId: 'used-as-biofuel'
              toUuid: '2-you-you-eye-dee'
            rawData: '{"$set":{"$hello":true}}'

          @sut.do request, (error, @response) => done error

        it 'should respond with a 200', ->
          expect(@response.metadata.code).to.equal 200

        describe 'when the record is retrieved', ->
          beforeEach (done) ->
            @deviceManager.findOne { uuid: { $exists: true } }, (error, @device) =>
              done error

          it 'should update the record', ->
            expect(@device.$hello).to.be.true
