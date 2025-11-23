import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  Image,
  StyleSheet,
  TouchableOpacity,
  SafeAreaView,
  ActivityIndicator,
  Platform,
  ScrollView,
} from 'react-native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { RouteProp } from '@react-navigation/native';
import { RootStackParamList } from '../../App';

type ResultScreenNavigationProp = NativeStackNavigationProp<
  RootStackParamList,
  'Result'
>;

type ResultScreenRouteProp = RouteProp<RootStackParamList, 'Result'>;

interface Props {
  navigation: ResultScreenNavigationProp;
  route: ResultScreenRouteProp;
}

const ResultScreen: React.FC<Props> = ({ navigation, route }) => {
  const { imageUri, sideImageUri } = route.params;
  const [frontImageError, setFrontImageError] = useState(false);
  const [sideImageError, setSideImageError] = useState(false);
  const [frontLoading, setFrontLoading] = useState(true);
  const [sideLoading, setSideLoading] = useState(!!sideImageUri);

  // For Android content URIs, we need to use them directly
  const displayFrontUri = Platform.OS === 'android' && imageUri.startsWith('content://')
    ? imageUri
    : imageUri.startsWith('file://')
    ? imageUri
    : `file://${imageUri}`;
    
  const displaySideUri = sideImageUri 
    ? (Platform.OS === 'android' && sideImageUri.startsWith('content://')
      ? sideImageUri
      : sideImageUri.startsWith('file://')
      ? sideImageUri
      : `file://${sideImageUri}`)
    : null;

  useEffect(() => {
    console.log('Result screen - Front Image URI:', imageUri);
    console.log('Result screen - Side Image URI:', sideImageUri);
    console.log('Result screen - Display Front URI:', displayFrontUri);
    console.log('Result screen - Display Side URI:', displaySideUri);
  }, [imageUri, sideImageUri, displayFrontUri, displaySideUri]);

  const handleRetake = () => {
    navigation.navigate('Camera');
  };

  const handleDone = () => {
    navigation.navigate('Intro');
  };

  return (
    <SafeAreaView style={styles.container}>
      <ScrollView style={styles.content} contentContainerStyle={styles.scrollContent}>
        <Text style={styles.title}>Perfect Shots! 📸</Text>
        
        {/* Both Images Side by Side */}
        <View style={styles.imagesRow}>
          {/* Front Pose Image */}
          <View style={styles.imageSection}>
            <Text style={styles.imageLabel}>Front Pose</Text>
            <View style={styles.imageContainer}>
              {frontLoading && (
                <View style={styles.loadingContainer}>
                  <ActivityIndicator size="large" color="#007AFF" />
                </View>
              )}
              
              {frontImageError ? (
                <View style={styles.errorContainer}>
                  <Text style={styles.errorText}>Failed to load</Text>
                </View>
              ) : (
                <Image
                  source={{ uri: displayFrontUri }}
                  style={styles.image}
                  resizeMode="cover"
                  onLoad={() => {
                    setFrontLoading(false);
                    console.log('Front image loaded successfully');
                  }}
                  onError={(error) => {
                    setFrontLoading(false);
                    setFrontImageError(true);
                    console.error('Front image load error:', error.nativeEvent.error);
                  }}
                />
              )}
            </View>
          </View>

          {/* Side Pose Image */}
          {displaySideUri && (
            <View style={styles.imageSection}>
              <Text style={styles.imageLabel}>Side Pose</Text>
              <View style={styles.imageContainer}>
                {sideLoading && (
                  <View style={styles.loadingContainer}>
                    <ActivityIndicator size="large" color="#007AFF" />
                  </View>
                )}
                
                {sideImageError ? (
                  <View style={styles.errorContainer}>
                    <Text style={styles.errorText}>Failed to load</Text>
                  </View>
                ) : (
                  <Image
                    source={{ uri: displaySideUri }}
                    style={styles.image}
                    resizeMode="cover"
                    onLoad={() => {
                      setSideLoading(false);
                      console.log('Side image loaded successfully');
                    }}
                    onError={(error) => {
                      setSideLoading(false);
                      setSideImageError(true);
                      console.error('Side image load error:', error.nativeEvent.error);
                    }}
                  />
                )}
              </View>
            </View>
          )}
        </View>

        <View style={styles.buttonContainer}>
          <TouchableOpacity style={styles.retakeButton} onPress={handleRetake}>
            <Text style={styles.retakeButtonText}>📷 Retake Photos</Text>
          </TouchableOpacity>

          <TouchableOpacity style={styles.doneButton} onPress={handleDone}>
            <Text style={styles.doneButtonText}>✓ Done</Text>
          </TouchableOpacity>
        </View>
      </ScrollView>
    </SafeAreaView>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#000',
  },
  content: {
    flex: 1,
  },
  scrollContent: {
    padding: 20,
  },
  title: {
    fontSize: 28,
    fontWeight: 'bold',
    color: '#fff',
    textAlign: 'center',
    marginTop: 20,
    marginBottom: 20,
  },
  imagesRow: {
    flexDirection: 'row',
    gap: 12,
    marginBottom: 24,
  },
  imageSection: {
    flex: 1,
  },
  imageLabel: {
    fontSize: 16,
    fontWeight: '600',
    color: '#fff',
    marginBottom: 8,
    textAlign: 'center',
  },
  imageContainer: {
    height: 400,
    backgroundColor: '#1a1a1a',
    borderRadius: 12,
    overflow: 'hidden',
  },
  image: {
    width: '100%',
    height: '100%',
  },
  buttonContainer: {
    gap: 12,
    marginTop: 12,
  },
  retakeButton: {
    backgroundColor: '#333',
    padding: 18,
    borderRadius: 12,
    alignItems: 'center',
  },
  retakeButtonText: {
    color: '#fff',
    fontSize: 18,
    fontWeight: '600',
  },
  doneButton: {
    backgroundColor: '#007AFF',
    padding: 18,
    borderRadius: 12,
    alignItems: 'center',
  },
  doneButtonText: {
    color: '#fff',
    fontSize: 18,
    fontWeight: '600',
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  loadingText: {
    color: '#fff',
    fontSize: 16,
    marginTop: 12,
  },
  errorContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 20,
  },
  errorText: {
    color: '#ff4444',
    fontSize: 14,
    fontWeight: 'bold',
    textAlign: 'center',
  },
  errorSubtext: {
    color: '#999',
    fontSize: 12,
    textAlign: 'center',
  },
});

export default ResultScreen;

