//
//  sqSqueakSoundCoreAudio.m
//  SqueakNoOGLIPhone
//
//  Created by John M McIntosh on 11/10/08.
/*
 Some of this code was funded via a grant from the European Smalltalk User Group (ESUG)
 Copyright (c) 2008 Corporate Smalltalk Consulting Ltd. All rights reserved.
 MIT License
 Permission is hereby granted, free of charge, to any person
 obtaining a copy of this software and associated documentation
 files (the "Software"), to deal in the Software without
 restriction, including without limitation the rights to use,
 copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the
 Software is furnished to do so, subject to the following
 conditions:
 
 The above copyright notice and this permission notice shall be
 included in all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 OTHER DEALINGS IN THE SOFTWARE.
 
 The end-user documentation included with the redistribution, if any, must include the following acknowledgment: 
 "This product includes software developed by Corporate Smalltalk Consulting Ltd (http://www.smalltalkconsulting.com) 
 and its contributors", in the same place and form as other third-party acknowledgments. 
 Alternately, this acknowledgment may appear in the software itself, in the same form and location as other 
 such third-party acknowledgments.
 */

#import "sqSqueakSoundCoreAudio.h"

#import <AVFoundation/AVFoundation.h>

#define SqueakFrameSize    4    // guaranteed (see class SoundPlayer)
extern struct VirtualMachine* interpreterProxy;

void MyAudioQueueOutputCallback (void *inUserData,
                                 AudioQueueRef        inAQ,
                                 AudioQueueBufferRef  inBuffer);

void MyAudioQueueOutputCallback (void *inUserData,
                                 AudioQueueRef        inAQ,
                                 AudioQueueBufferRef  inBuffer) {
    
    sqSqueakSoundCoreAudio * myInstance = (__bridge sqSqueakSoundCoreAudio *)inUserData;
                   
    soundAtom    *atom = [myInstance.soundOutQueue returnOldest];
    
    UInt32 startOffset = 0;
    UInt32 endOffset = 0;
    
    if (inBuffer->mAudioDataBytesCapacity >= atom.byteCount) {
            atom = [myInstance.soundOutQueue returnAndRemoveOldest];
            inBuffer->mAudioDataByteSize = (int) atom.byteCount;
            memcpy(inBuffer->mAudioData,atom.data,atom.byteCount);
        //NSLog(@"%i Fill sound buffer with %i bytesA",ioMSecs(),inBuffer->mAudioDataByteSize);
    } else {
            inBuffer->mAudioDataByteSize = (int) MIN(atom.byteCount - atom.startOffset,inBuffer->mAudioDataBytesCapacity);
            memcpy(inBuffer->mAudioData,atom.data+atom.startOffset,inBuffer->mAudioDataByteSize);
            atom.startOffset = atom.startOffset + inBuffer->mAudioDataByteSize;
            if (atom.startOffset == atom.byteCount) {
                //now it's empty
                [myInstance.soundOutQueue returnAndRemoveOldest];
            }
        //NSLog(@"%i Fill sound buffer with %i bytesB",ioMSecs(),inBuffer->mAudioDataByteSize);
    }
    
    if([myInstance.soundOutQueue pendingElements] == 0){
        interpreterProxy->signalSemaphoreWithIndex(myInstance.semaIndexForOutput);
        return;
    }
    
    AudioQueueEnqueueBufferWithParameters(inAQ,inBuffer,0,NULL,startOffset,endOffset,0,NULL,NULL,NULL);
    
    UInt32 outNumberOfFramesPrepared;
    AudioQueuePrime(inAQ,inBuffer->mAudioDataByteSize,&outNumberOfFramesPrepared);
    
    LgInfo(@"o%d,%d,%u,%u", myInstance.semaIndexForOutput, myInstance.outputIsRunning,(unsigned int)outNumberOfFramesPrepared, (unsigned int)[myInstance.soundOutQueue pendingElements]);
    interpreterProxy->signalSemaphoreWithIndex(myInstance.semaIndexForOutput);    
    
}
void    MyAudioQueuePropertyListenerProc (  void *              inUserData,
                                          AudioQueueRef           inAQ,
                                          AudioQueuePropertyID    inID);

void    MyAudioQueuePropertyListenerProc (  void *              inUserData,
                                          AudioQueueRef           inAQ,
                                          AudioQueuePropertyID    inID)
{
    sqInt    isRunning;
    UInt32 size = sizeof(isRunning);
    sqSqueakSoundCoreAudio * myInstance = (__bridge sqSqueakSoundCoreAudio *)inUserData;

    AudioQueueGetProperty (inAQ, kAudioQueueProperty_IsRunning, &isRunning, &size);
    myInstance.outputIsRunning = isRunning;
    LgInfo(@"outputIsRunning: %i", isRunning);

}

void MyAudioQueueInputCallback (
                                void                                *inUserData,
                                AudioQueueRef                       inAQ,
                                AudioQueueBufferRef                 inBuffer,
                                const AudioTimeStamp                *inStartTime,
                                UInt32                              inNumberPacketDescriptions,
                                const AudioStreamPacketDescription  *inPacketDescs);

void MyAudioQueueInputCallback (
                                void                                *inUserData,
                                AudioQueueRef                       inAQ,
                                AudioQueueBufferRef                 inBuffer,
                                const AudioTimeStamp                *inStartTime,
                                UInt32                              inNumberPacketDescriptions,
                                const AudioStreamPacketDescription  *inPacketDescs) {
    
    sqSqueakSoundCoreAudio * myInstance = (__bridge sqSqueakSoundCoreAudio *)inUserData;
    
    if (myInstance.inputIsRunning == 0)
        return;
    
    if (inNumberPacketDescriptions > 0) {
        soundAtom *atom = [[soundAtom alloc] initWith: inBuffer->mAudioData count: inBuffer->mAudioDataByteSize];
        [myInstance.soundInQueue addItem: atom];
    }
    
    AudioQueueEnqueueBuffer (inAQ, inBuffer, 0, NULL);
    
    LgInfo(@"i%d", myInstance.semaIndexForInput);
    interpreterProxy->signalSemaphoreWithIndex(myInstance.semaIndexForInput);    
 }


@implementation soundAtom
@synthesize    data; 
@synthesize    byteCount;
@synthesize    startOffset;

- initWith: (char*) buffer count: (usqInt) bytes {
    data = malloc(bytes);
    memcpy(data,buffer,bytes);
    byteCount = bytes;
    startOffset = 0;
    return self;
}

- (void)dealloc {
    if (data) free(data);
    data = 0;
    byteCount = 0;
    startOffset = 0;
}

@end

@implementation sqSqueakSoundCoreAudio
@synthesize outputAudioQueue;
@synthesize inputAudioQueue;
@synthesize semaIndexForOutput;
@synthesize bufferSizeForOutput;
@synthesize semaIndexForInput;
@synthesize bufferSizeForInput;
@synthesize    inputSampleRate;
@synthesize outputFormat;
@synthesize inputFormat;
@synthesize outputIsRunning;
@synthesize inputIsRunning;
@synthesize recordAllowed;
@synthesize soundOutQueue;
@synthesize soundInQueue;
@synthesize    outputBuffers;
@synthesize    inputBuffers;
@synthesize inputChannels;

-    (sqInt) soundInit {
    //NSLog(@"%i sound init",ioMSecs());
    self.outputAudioQueue = nil;
    self.inputAudioQueue = nil;
    self.semaIndexForOutput = 0;
    self.semaIndexForInput = 0;
    self.outputFormat = calloc(1,sizeof(AudioStreamBasicDescription));
    self.inputFormat = calloc(1,sizeof(AudioStreamBasicDescription));
    self.outputBuffers = calloc((unsigned)kNumberOfPlayBuffers,sizeof(AudioQueueBufferRef));
    self.inputBuffers = calloc((unsigned) kNumberOfBuffers,sizeof(AudioQueueBufferRef));
    soundOutQueue = [OldQueue new];
    soundInQueue = [OldQueue new];
    
    self.recordAllowed = NO;
    if([self initAudioSession] == NO){ return 0;}
    return 1;
    
}

- (sqInt) soundShutdown {
    //NSLog(@"%i sound shutdown",ioMSecs());
    if (self.outputAudioQueue) {
        [self snd_StopAndDispose];
    }
    if (self.inputAudioQueue) {
        [self snd_StopRecording];
    }
    
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center removeObserver:self name:AVAudioSessionInterruptionNotification object: nil];
    [center removeObserver:self name:AVAudioSessionRouteChangeNotification object:nil];
    
    
    return 1;
}

- (void) dealloc{
    outputAudioQueue = nil;
    inputAudioQueue = nil;
    
    if(outputFormat){
        free(outputFormat);
        outputFormat = NULL;
    }
    if(inputFormat){
        free(inputFormat);
        inputFormat = NULL;
    }
    if(outputBuffers){
        free(outputBuffers);
        outputBuffers = NULL;
    }
    if(inputBuffers){
        free(inputBuffers);
        inputBuffers = NULL;
    }
}

- (sqInt) snd_Start: (sqInt) frameCount samplesPerSec: (sqInt) samplesPerSec stereo: (sqInt) stereo semaIndex: (sqInt) semaIndex {
    //NSLog(@"%i sound start playing frame count %i samples %i",ioMSecs(),frameCount,samplesPerSec);
    OSStatus result;
    int nChannels= 1 + (int)stereo;
    
    if (frameCount <= 0 || samplesPerSec <= 0 || stereo < 0 || stereo > 1) 
        return interpreterProxy->primitiveFail();

    LgInfo(@"!!snd_Start: %i samples:%i stereo:%i",semaIndex, samplesPerSec, stereo);
    
    self.semaIndexForOutput = semaIndex;
    
    BOOL descChanged = NO;
    if(!self.outputFormat){
       if(self.outputFormat->mSampleRate != samplesPerSec || self.outputFormat->mChannelsPerFrame != nChannels){
           descChanged = YES;
           LgInfo(@"ASBD changed");
       }
    }
    
    /* we want to create a new audio queue only if we have to */
    if (self.outputAudioQueue == nil || descChanged) {
        
        if ([self startAudioSession] == NO){return 0;}
        
        LgInfo(@"create outputAudioQueue");
        
        AudioStreamBasicDescription check;
        bzero(&check,sizeof(AudioStreamBasicDescription));
        
        check.mSampleRate = (Float64)samplesPerSec;
        check.mFormatID = kAudioFormatLinearPCM;
        check.mFormatFlags = kAudioFormatFlagsNativeEndian | kLinearPCMFormatFlagIsSignedInteger;
        check.mBytesPerPacket   = SqueakFrameSize / (3 - nChannels);
        check.mFramesPerPacket  = 1;
        check.mBytesPerFrame    = SqueakFrameSize / (3 - nChannels);
        check.mChannelsPerFrame = nChannels;
        check.mBitsPerChannel   = 16;
        
        //NSLog(@"%i create new audioqueue",ioMSecs());
        if (self.outputAudioQueue) {[self snd_StopAndDispose];}
        AudioQueueRef newQueue;
        
        *self.outputFormat = check;
        result =  AudioQueueNewOutput (self.outputFormat, &MyAudioQueueOutputCallback,
                                   (__bridge void*) self,
                                   NULL,
                                   NULL,
                                   0,
                                   &newQueue);
    
        if (result) 
            return interpreterProxy->primitiveFail();
        self.outputAudioQueue = newQueue;
    
        AudioQueueAddPropertyListener (self.outputAudioQueue, kAudioQueueProperty_IsRunning, MyAudioQueuePropertyListenerProc, (__bridge void * _Nullable)(self));
    
        self.bufferSizeForOutput = (unsigned) (SqueakFrameSize * nChannels * frameCount * 2);
        int i;
        UInt32 bufferSize = frameCount; //self.bufferSizeForOutput/16;
        for (i = 0; i < kNumberOfPlayBuffers; ++i) {
            result = AudioQueueAllocateBuffer(self.outputAudioQueue, bufferSize, &self.outputBuffers[i]);
            if(result)
                return interpreterProxy->primitiveFail();
        }
    } else {
        LgInfo(@"%i reuse audioqueue",ioMSecs());
    }
        
    return 1;
    
}

- (sqInt) snd_Stop {
    @synchronized(self) {
    LgInfo(@"!!snd_Stop!!");
    if (self.outputIsRunning == NO)
        return 1;
    NSLog(@"sound stop");
    if (!self.outputAudioQueue) 
        return 0;
    [self.soundOutQueue removeAll];
    if ([self stopOutputAudioQueue] == NO) {return 0;}
    
    self.outputIsRunning = NO;
    return 1;
    }
}

- (void) snd_Stop_Force {
    @synchronized(self) {
    LgInfo(@"!!snd_Stop_Force!!");
    if (!self.outputAudioQueue) 
        return;
    NSLog(@"sound stop force");
    if ([self stopOutputAudioQueue] == NO) {return;}
        
    if ([self stopAudioSession] == NO){ return;}
    self.outputIsRunning = NO;
    }
}


- (sqInt) snd_StopAndDispose {
    @synchronized(self) {
    LgInfo(@"!!snd_StopAndDispose!!");
    if (self.outputAudioQueue == nil)
        return 0;
    
    [self snd_Stop];
    if (self.outputIsRunning == NO)
        return 0;
    
    if ([self stopOutputAudioQueue] == NO) {return 0;}
        
    LgInfo(@"outputAudioQueue := nil");
    self.outputAudioQueue = nil;
    [[self soundOutQueue] removeAll];
    
    if ([self stopAudioSession] == NO){ return 0;}
    return 1;
    }
}

- (sqInt) snd_PlaySilence {
    LgInfo(@"snd_PlaySilence");
    interpreterProxy->success(false);
    return 8192;
    
}

- (sqInt) snd_AvailableSpace {
    if (!self.outputAudioQueue) return interpreterProxy->primitiveFail();
    if ([self.soundOutQueue pendingElements] > kNumberOfPlayBuffers-1) return 0;
    return self.bufferSizeForOutput;
}

- (sqInt) snd_PlaySamplesFromAtLength: (sqInt) frameCount arrayIndex: (char *) arrayIndex startIndex: (usqInt) startIndex {
    OSStatus result;
    usqInt byteCount= frameCount * SqueakFrameSize;
    
    if (!self.outputAudioQueue) 
        return interpreterProxy->primitiveFail();
    if (frameCount <= 0 || startIndex > byteCount) 
        return interpreterProxy->primitiveFail();
    //NSLog(@"%i sound place samples on queue frames %i startIndex %i count %i",ioMSecs(),frameCount,startIndex,byteCount-startIndex);
        
    soundAtom *atom = [[soundAtom alloc] initWith: arrayIndex+startIndex count: (unsigned) (byteCount-startIndex)];
    [self.soundOutQueue addItem: atom];
    
    if (!self.outputIsRunning && ([self.soundOutQueue pendingElements] == kNumberOfPlayBuffers)) {
        int i;
        result =  AudioQueueStart (self.outputAudioQueue,NULL);
        for (i = 0; i < kNumberOfPlayBuffers; ++i) {
            MyAudioQueueOutputCallback ((__bridge void *)(self),self.outputAudioQueue,self.outputBuffers[i]);
        }
        if(result != noErr){
            LgError(@"snd_PlaySamplesFromAtLength status: %d", (int)result);
        }
        //Force it as running
        self.outputIsRunning = YES;
    }
    return 1;
}

- (sqInt) snd_InsertSamplesFromLeadTime: (sqInt) frameCount srcBufPtr: (char*) srcBufPtr samplesOfLeadTime: (sqInt) samplesOfLeadTime {
    //NOT IMPLEMEMENTED 
    return 0;
}

- (void) prepareInputAudioParams:(sqInt)semaIndex desiredSamplesPerSec:(sqInt)desiredSamplesPerSec isStereo:(int)isStereo {
    LgInfo(@"setting inputFormat");
    self.semaIndexForInput = semaIndex;
    self.inputSampleRate = (float) desiredSamplesPerSec;
    self.inputChannels = 1 + isStereo;
    self.inputFormat->mSampleRate = (Float64)desiredSamplesPerSec;
    self.inputFormat->mFormatID = kAudioFormatLinearPCM;
    self.inputFormat->mFormatFlags = kAudioFormatFlagsNativeEndian | kLinearPCMFormatFlagIsSignedInteger 
    | kAudioFormatFlagIsPacked ;
    
    self.inputFormat->mBytesPerPacket   = (int) SqueakFrameSize / (3 - (int)self.inputChannels);
    self.inputFormat->mFramesPerPacket  = 1;
    self.inputFormat->mBytesPerFrame    =(int)  SqueakFrameSize / (3 - (int)self.inputChannels);
    self.inputFormat->mChannelsPerFrame =(int) self.inputChannels;
    self.inputFormat->mBitsPerChannel   = 16;
    
    sqInt frameCount = 5288 * desiredSamplesPerSec / 44100;
    self.bufferSizeForInput = (unsigned) (SqueakFrameSize * self.inputChannels * frameCount * 2/4);
    //Currently squeak does this thing where it stops yet leaves data in queue, this causes us to lose dota if the buffer is too big
}

- (bool) prepareInputAudioBuffers {
    OSStatus result;
    for (int i = 0; i < kNumberOfBuffers; ++i) {
        result = AudioQueueAllocateBuffer(self.inputAudioQueue, self.bufferSizeForInput, &self.inputBuffers[i]);
        if(result != noErr){
            LgError(@"AudioQueueAllocateBuffer status: %d", (int)result);
            return NO;
        }
        result = AudioQueueEnqueueBuffer(self.inputAudioQueue,self.inputBuffers[i],0,NULL);
        if(result != noErr){
            LgError(@"AudioQueueEnqueueBuffer status: %d", (int)result);
            return NO;
        }
    }
    return YES;
}

- (sqInt) recordingTrialFailed {
    inputIsRunning = 0;
    return 0;
}

- (sqInt) recordingStopTrialFailed {
    inputIsRunning = 1;
    return 0;
}

- (sqInt) snd_StartRecording: (sqInt) desiredSamplesPerSec stereo: (sqInt) stereo semaIndex: (sqInt) semaIndex {
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    if([audioSession respondsToSelector:@selector(requestRecordPermission:)])
    {
        [audioSession requestRecordPermission:^(BOOL allowed){
            LgInfo(@"Allow microphone use? %d", allowed);
            self.recordAllowed = allowed;
        }];
    } else {
        self.recordAllowed = YES;
    }
    return [self basicStartRecording:desiredSamplesPerSec stereo:stereo semaIndex:semaIndex];
}

- (sqInt) basicStartRecording: (sqInt) desiredSamplesPerSec stereo: (sqInt) stereo semaIndex: (sqInt) semaIndex {
    @synchronized(self){
        
        if(outputIsRunning == YES) {
            LgInfo(@" StartRecording: outputIsRunning");
            return interpreterProxy->primitiveFail();
        }
        if(inputIsRunning == 1) {
            LgInfo(@" StartRecording: inputIsRunning");
            return interpreterProxy->primitiveFail();
        }
    
        LgInfo(@"snd_StartRecording ParamsCheck (sampleRate:%d sema:%d)", desiredSamplesPerSec, semaIndex);
        if (desiredSamplesPerSec <= 0){
            LgError(@"such sample rate is not supported: %d", desiredSamplesPerSec);
            return interpreterProxy->primitiveFail();
        }
        
        int tmpStereo = stereo;
        if(tmpStereo != 0){
            LgWarn(@"do not support stereo %d, so use 1 channel", tmpStereo);
            tmpStereo = 0;
        }
        
        LgInfo(@"==snd_StartRecording begin");
        inputIsRunning = 1;
        [self prepareInputAudioParams:semaIndex desiredSamplesPerSec:desiredSamplesPerSec isStereo:tmpStereo];
        
        LgInfo(@"prepare newQueue");
        AudioQueueRef newQueue;
        OSStatus result =  AudioQueueNewInput (self.inputFormat, &MyAudioQueueInputCallback,
                                               (__bridge void*) self,
                                               NULL,
                                               NULL,
                                               0,
                                               &newQueue);
        if (result != noErr) {
            LgError(@"AudioQueueNewInput status: %d", (int)result);
            [self recordingTrialFailed];
            return interpreterProxy->primitiveFail();
        }
        self.inputAudioQueue = newQueue;
        
        if([self prepareInputAudioBuffers] == NO){
            [self recordingTrialFailed];
            return interpreterProxy->primitiveFail();
        }
        
        if ([self startAudioSession] == NO){ return [self recordingTrialFailed];}
        if ([self ensureAudioSessionRecordingMode] == NO){ return [self recordingTrialFailed];}
        
        result =  AudioQueueStart(self.inputAudioQueue,NULL);
        if(result != noErr){
            LgError(@"AudioQueueStart status: %d", (int)result);
            [self recordingTrialFailed];
            return interpreterProxy->primitiveFail();
        }
        LgInfo(@"==snd_StartRecording end");
        
        if (!self.recordAllowed){
            LgWarn(@"record is not allowed!!");
        }
        
        return 0;
    }
}

- (sqInt) snd_StopRecording {
    @synchronized(self) {
        
    if(inputIsRunning == 0) {
        return 0;
    }
    if(self.inputAudioQueue == null){
        return 0;
    }
    
    LgInfo(@"==snd_StopRecording begin");
    inputIsRunning = 0;
    OSStatus result = AudioQueueStop (self.inputAudioQueue,true);  //This implicitly invokes AudioQueueReset
    if (result != noErr){
        LgError(@"AudioQueueStop fail: %i", (int)result);
        return [self recordingStopTrialFailed];
    }
    
    result = AudioQueueDispose (self.inputAudioQueue,true);
    if (result != noErr){
        LgError(@"AudioQueueDispose fail: %i", (int)result);
        return [self recordingStopTrialFailed];
    }
    
    LgInfo(@"released inputAudioQueue");
    self.inputAudioQueue = nil;
    [self.soundInQueue removeAll];
    
    LgInfo(@"==snd_StopRecording end");
    return 1;
    }
}

- (double) snd_GetRecordingSampleRate {
    if (!self.recordAllowed){
        return 0;
    }
    if (self.inputSampleRate == null){
        return interpreterProxy->primitiveFail();
    }

    return inputSampleRate;
}

- (sqInt) snd_RecordSamplesIntoAtLength: (char*) arrayIndex startSliceIndex: (usqInt) startSliceIndex bufferSizeInBytes: (usqInt) bufferSizeInBytes {
    
    usqInt    count;
    
    if (!self.inputAudioQueue) 
        return interpreterProxy->primitiveFail();
    if (startSliceIndex > bufferSizeInBytes) 
        return interpreterProxy->primitiveFail();

    usqInt    start= startSliceIndex * SqueakFrameSize / 2;
    soundAtom    *atom = [self.soundInQueue returnOldest];
    if (atom == nil) 
        return 0;
    if (bufferSizeInBytes-start >= atom.byteCount && atom.startOffset == 0) {
        atom = [self.soundInQueue returnAndRemoveOldest];
        memcpy(arrayIndex+start,atom.data,atom.byteCount);
        count= MIN(atom.byteCount, bufferSizeInBytes - start);
        return count / (SqueakFrameSize / 2) / self.inputChannels;
    } else {
        count= MIN(atom.byteCount-atom.startOffset, bufferSizeInBytes - start);
        memcpy(arrayIndex+start,atom.data+atom.startOffset,count);
        atom.startOffset = atom.startOffset + (count);
        if (atom.startOffset == atom.byteCount) {
            atom = [self.soundInQueue returnAndRemoveOldest]; //ignore now it's empty
        }
        return count / (SqueakFrameSize / 2) / self.inputChannels;
    }
        
}

#pragma mark - private
- (BOOL) stopOutputAudioQueue {
    OSStatus result = AudioQueueStop (self.outputAudioQueue,true);  //This implicitly invokes AudioQueueReset
    if (result != noErr) {
        LgError(@"snd_Stop>AudioQueueStop status: %d", (int)result);
        return NO;
    }
    return YES;
}

#pragma mark - Initialization
- (BOOL) initAudioSession
{
    [self ensureAudioSessionRecordingMode];
    
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self selector:@selector(sessionDidInterrupt:) name:AVAudioSessionInterruptionNotification object:nil];
    [center addObserver:self selector:@selector(sessionRouteDidChange:) name:AVAudioSessionRouteChangeNotification object:nil];
    [center addObserver:self selector:@selector(mediaServicesWereReset:) name:AVAudioSessionMediaServicesWereResetNotification object:nil];
    return YES;
}

#pragma mark - Callback

- (void) stopIfRunning
{
    if (self.outputIsRunning) {
        LgInfo(@"outputIsRunning-> snd_Stop");
        [self snd_StopAndDispose];
    }
    if (self.inputIsRunning) {
        LgInfo(@"inputIsRunning-> snd_StopRecording");
        [self snd_StopRecording];
        [self stopAudioSession];
    }
}


- (void) sessionDidInterrupt:(NSNotification *)notification
{
    switch ([notification.userInfo[AVAudioSessionInterruptionTypeKey] intValue]) {
        case AVAudioSessionInterruptionTypeBegan:
            LgInfo(@"Interruption began");
            [self stopIfRunning];
            break;
        case AVAudioSessionInterruptionTypeEnded:
            LgInfo(@"Interruption ended!!");

        default:
            break;
    }
}

- (void) sessionRouteDidChange:(NSNotification *)notification
{
    LgInfo(@"sessionRouteDidChange: ");
    [self stopIfRunning];
}

- (void) mediaServicesWereReset:(NSNotification *)notification
{
    LgInfo(@"mediaServicesWereReset: ");
    [self stopIfRunning];
}

#pragma mark - AudioSesssion
- (BOOL) startAudioSession
{
    LgInfo(@"###startAudioSession");
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    NSError *err = nil;
    [audioSession setActive:YES error:&err];
    if(err){
        LgError(@"audioSession: %@ %ld %@", [err domain], (long)err.code, [[err userInfo] description]);
        return NO;
    }
    
    if (! audioSession.inputAvailable) {
        LgError(@"Audio input hardware not available");
        return NO;
    }
    
    return YES;
}

- (BOOL) ensureAudioSessionRecordingMode
{
    NSError *err = nil;
    [[AVAudioSession sharedInstance] setCategory: AVAudioSessionCategoryPlayAndRecord error: &err];
    if(err){
        LgError(@"audioSession: %@ %ld %@", [err domain], (long)err.code, [[err userInfo] description]);
        return NO;
    }
    return YES;
}

- (BOOL) stopAudioSession
{
    LgInfo(@"+++stopAudioSession");
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    NSError *err = nil;
    [audioSession setActive:NO error:&err];
    if(err){
        LgError(@"audioSession: %@ %ld %@", [err domain], (long)err.code, [[err userInfo] description]);
        return NO;
    }
    
    return YES;
}

@end


